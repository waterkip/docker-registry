#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Sub::Override;
use HTTP::Request;

use Docker::Registry::Auth::Gitlab;

{
    my $auth = Docker::Registry::Auth::Gitlab->new(
        username => 'foo',
        password => 'bar',
    );

    my $jwt = $auth->jwt;
    isa_ok($jwt, 'URI', "Got a JWT URI");

    my $scope = $auth->_build_scope;
    is($scope, 'registry:catalog:*', "scope is set to 'registry:catalog:*'");

    {
        # Cannot change the value, so bypass it :)
        my $attr = $auth->meta->find_attribute_by_name('repo');
        $attr->set_value($auth, 'foobar');

        my $scope = $auth->_build_scope;
        is($scope, 'repository:foobar:pull,push',
            "scope is set to 'repository:foobar:pull,push'");
    }

    my $uri = $auth->_build_token_uri;
    isa_ok($uri, 'URI', ".. and we have a token URI");
    is($uri->host,     'gitlab.com', ".. with the correct hostname");
    is($uri->userinfo, 'foo:bar',    ".. and the correct login details");

    # Override HTTP::Tiny get so we don't need a network connection
    my $override = Sub::Override->new(
        "HTTP::Tiny::get" => sub {
            return {
                success => 1,
                content => '{"token":"mysupersecrettoken"}',
            };
        }
    );

    is($auth->token, "mysupersecrettoken",
        "Go the super secret token from gitlab!");

    my $req = HTTP::Request->new('GET', $uri);
    $req = $auth->authorize($req);

    isa_ok($req, "HTTP::Request", "->authorize works too");
    is(
        $req->headers->header("authorization"),
        "Bearer mysupersecrettoken",
        ".. with the correct header"
    );

    $override->restore;
}

SKIP: {

    note "Live test, set GITLAB_USERNAME, GITLAB_TOKEN to run this"
    . " test. Optionally set GITLAB_JWT if you want to test against a"
    . " self-hosted server. GITLAB_REPO can also be set.";

    skip "LIVE tests", 1 unless grep { /^GITLAB_/ } keys %ENV;

    my $auth = Docker::Registry::Auth::Gitlab->new(
        username => $ENV{GITLAB_USERNAME},
        password => $ENV{GITLAB_TOKEN},
        $ENV{GITLAB_JWT}  ? (jwt  => $ENV{GITLAB_JWT})  : (),
        $ENV{GITLAB_REPO} ? (repo => $ENV{GITLAB_REPO}) : (),
    );

    my $token = $auth->token;
    isnt($token, undef, "We got '$token' from gitlab");

}
done_testing;