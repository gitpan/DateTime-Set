#!/usr/bin/perl -w

use strict;

use Test::More;
plan tests => 6;

use DateTime;
use DateTime::Duration;
use DateTime::SpanSet;
use DateTime::Span;
use DateTime::Set;
# use warnings;

#======================================================================
# add duration to recurrence
#====================================================================== 

use constant INFINITY     =>       100 ** 100 ** 100 ;
use constant NEG_INFINITY => -1 * (100 ** 100 ** 100);

my $res;

my $t1 = new DateTime( year => '1810', month => '08', day => '22' );
my $t2 = new DateTime( year => '1810', month => '11', day => '24' );
my $s1 = DateTime::Set->from_datetimes( dates => [ $t1, $t2 ] );

my $dur = new DateTime::Duration( hours => 1  );

my $month_callback = sub {
            $_[0]->truncate( to => 'month' )
                 ->add( months => 1 );
        };

{
    # "START"
    my $months = DateTime::Set->from_recurrence( 
        recurrence => $month_callback, 
        start => $t1,
    );
    $res = $months->min;
    $res = $res->ymd if ref($res);
    ok( $res eq '1810-09-01', 
        "min() - got $res" );

    $res = $months->add_duration( $dur )->min;
    $res = $res->datetime if ref($res);
    ok( $res eq '1810-09-01T01:00:00',
        "min() - got $res" );
}

{
    # INTERSECTION
    my $months = DateTime::Set->from_recurrence(
        recurrence => $month_callback,
    );
    $res = $months->intersection(
               DateTime::Span->from_datetimes( after => $t1 )
           )->min;
    $res = $res->ymd if ref($res);
    ok( $res eq '1810-09-01',
        "min() - got $res" );

    $res = $months->add_duration( $dur )
           ->intersection(
               DateTime::Span->from_datetimes( after => $t1 )
           )->min;
    $res = $res->datetime if ref($res);
    ok( $res eq '1810-09-01T01:00:00',
        "min() - got $res" );
}

#======================================================================
# create spanset by adding duration to recurrence
#======================================================================

{
    # SPANSET FROM RECURRENCE AND DURATION

    my $months = DateTime::Set->from_recurrence(
        recurrence => $month_callback,
    );

    my $spans = DateTime::SpanSet->from_set_and_duration( 
                 set => $months,
                 duration => $dur 
    );

    $res = $spans->intersection(
               DateTime::Span->from_datetimes( after => $t1 )
           );
    # this was written step-by-step to help debugging
    my $first_span = $res->{set}->first;
    $res = $first_span->min;
    $res = $res->datetime if ref($res);
    ok( $res eq '1810-09-01T00:00:00',
        "min() - got $res" );
    $res = $first_span->max;
    $res = $res->datetime if ref($res);
    ok( $res eq '1810-09-01T01:00:00',
        "max() - got $res" );
}

1;

