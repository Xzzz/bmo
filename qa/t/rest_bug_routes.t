#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#####################################################
# Tests for the REST bug routes not covered by the  #
# per-method tests: Bug.get permissive mode,        #
# GET /rest/bug/, quicksearch, the                  #
# Bug.possible_duplicates param checks and OPTIONS  #
#####################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use QA::Util       qw(get_config);
use QA::REST::Util qw(api_headers);

use Test::Mojo;
use Test::More;

my $config  = get_config();
my $url     = Bugzilla->localconfig->urlbase;
my $headers = api_headers($config->{admin_user_api_key});

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

# Permissive mode returns the bugs it can, and a fault for each other id.
$t->get_ok($url
    . 'rest/bug/public_bug?ids=99999999&permissive=1&include_fields=id' =>
    $headers)
  ->status_is(200)
  ->json_is('/bugs/0/id'            => 2)
  ->json_is('/faults/0/id'          => 99999999)
  ->json_is('/faults/0/faultCode'   => 101)
  ->json_is('/faults/0/faultString' => 'Bug 99999999 does not exist.');

# Without it, the unknown bug is an error.
$t->get_ok($url . 'rest/bug/99999999' => $headers)->status_is(404)
  ->json_is('/code' => 101);

# GET /rest/bug/ takes the bug ids from the query string.
$t->get_ok($url . 'rest/bug/?ids=public_bug&include_fields=id' => $headers)
  ->status_is(200)
  ->json_is('/bugs/0/id' => 2);

# Quicksearch keeps the other search params, such as limit.
$t->get_ok($url . 'rest/bug?quicksearch=ALL&limit=1&include_fields=id' =>
    $headers)
  ->status_is(200)
  ->json_is('/bugs/0/id' => 1)
  ->json_hasnt('/bugs/1');
$t->get_ok($url . 'rest/bug?quicksearch=public_bug&include_fields=id' =>
    $headers)
  ->status_is(200)
  ->json_is('/bugs/0/id' => 2);

# 'load' asks quicksearch to redirect to the search form; the API ignores it.
$t->get_ok(
  $url . 'rest/bug?quicksearch=ALL&load=1&limit=1&include_fields=id' => $headers)
  ->status_is(200)
  ->json_is('/bugs/0/id' => 1);

# Bug.possible_duplicates rejects unknown params and needs id or summary.
$t->get_ok($url . 'rest/bug/possible_duplicates?summary=bug&foo=1' => $headers)
  ->status_is(400)
  ->json_is('/code' => 53);
$t->get_ok($url
    . 'rest/bug/possible_duplicates?summary=bug&exclude_fields=id' =>
    $headers)
  ->status_is(400)
  ->json_is('/code' => 53);
$t->get_ok($url . 'rest/bug/possible_duplicates' => $headers)->status_is(400)
  ->json_is('/code' => 50);
$t->get_ok($url
    . 'rest/bug/possible_duplicates?summary=testing&include_fields=id' =>
    $headers)
  ->status_is(200)
  ->json_has('/bugs');

# OPTIONS lists the methods of each route.
$t->options_ok($url . 'rest/bug')->status_is(200)
  ->header_is(Allow => 'GET, POST');
$t->options_ok($url . 'rest/bug/public_bug')->status_is(200)
  ->header_is(Allow => 'GET, PUT');
$t->options_ok($url . 'rest/bug/public_bug/history')->status_is(200)
  ->header_is(Allow => 'GET');

done_testing();
