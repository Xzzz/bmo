#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bmo.test');
use Bugzilla::Test::MockDB;
use Bugzilla::Test::Util qw(create_bug create_user);
use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::User;
use Test2::V0;

# Bug history and bugmail read the flag changes made before flag_activity
# existed from bugs_activity, and only the newer ones from flag_activity.

create_user('automation@bmo.tld', '*');
Bugzilla->set_user(Bugzilla::User->super_user);
my $dbh = Bugzilla->dbh;

my $setter = create_user('setter@bmo.test', '*');
my $alice  = create_user('alice@bmo.test',  '*');
create_user('bob@bmo.test', '*');

my $bug_id = create_bug(
  short_desc  => 'Flag history test bug',
  comment     => 'Bug for the flag_activity history tests',
  bug_type    => 'defect',
  assigned_to => 'nobody@mozilla.org',
)->id;

my ($fieldid)
  = $dbh->selectrow_array(
  "SELECT id FROM fielddefs WHERE name = 'flagtypes.name'");
my ($review_id)
  = $dbh->selectrow_array("SELECT id FROM flagtypes WHERE name = 'review'");

sub add_flag_activity {
  my ($when, $flag_id, $who, $requestee_id, $status) = @_;
  $dbh->do(
    'INSERT INTO flag_activity
       (flag_when, type_id, flag_id, setter_id, who, requestee_id, bug_id,
        status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)', undef, $when, $review_id, $flag_id,
    $who->id, $who->id, $requestee_id, $bug_id, $status
  );
}

# Legacy changes, only in bugs_activity.
for my $row (
  ['2020-01-01 10:00:00', '',                      'review?(bob@bmo.test)'],
  ['2020-01-02 10:00:00', 'review?(bob@bmo.test)', ''],
  ['2020-01-03 10:00:00', '',                      'review+'],
  )
{
  $dbh->do(
    'INSERT INTO bugs_activity (bug_id, who, bug_when, fieldid, removed, added)
     VALUES (?, ?, ?, ?, ?, ?)', undef, $bug_id, $setter->id, $row->[0],
    $fieldid, $row->[1], $row->[2]
  );
}

# The last legacy change was also written to flag_activity, then the flag
# changed again once only flag_activity was written.
add_flag_activity('2020-01-03 10:00:00', 42, $setter, undef, '+');
add_flag_activity('2026-01-01 10:00:00', 42, $alice,  undef, '-');

my @expected = (
  ['setter@bmo.test', '',                      'review?(bob@bmo.test)'],
  ['setter@bmo.test', 'review?(bob@bmo.test)', ''],
  ['setter@bmo.test', '',                      'review+'],
  ['alice@bmo.test',  'review+',               'review-'],
);

my ($operations) = Bugzilla::Bug::GetBugActivity($bug_id);
my @history = map {
  my $who = $_->{who};
  map { [$who, $_->{removed}, $_->{added}] }
    grep { $_->{fieldname} eq 'flagtypes.name' } @{$_->{changes}}
} @$operations;
is(\@history, \@expected, 'history: each flag change once, with old value');

$dbh->do('UPDATE bugs SET lastdiffed = NULL WHERE bug_id = ?', undef, $bug_id);
my ($diffs) = Bugzilla::BugMail::_get_diffs(Bugzilla::Bug->new($bug_id),
  '2026-12-31 00:00:00', {});
my @mail = map { [$_->{who}->login, $_->{old}, $_->{new}] }
  grep { $_->{field_name} eq 'flagtypes.name' } @$diffs;
is(\@mail, \@expected, 'bugmail: each flag change once, with old value');

done_testing;
