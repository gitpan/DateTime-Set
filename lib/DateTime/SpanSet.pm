# Copyright (c) 2003 Flavio Soibelmann Glock. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package DateTime::SpanSet;

use strict;
use Carp;
use Params::Validate qw( validate SCALAR BOOLEAN OBJECT CODEREF ARRAYREF );
use Set::Infinite '0.44';
$Set::Infinite::PRETTY_PRINT = 1;   # enable Set::Infinite debug

use constant INFINITY     =>       100 ** 100 ** 100 ;
use constant NEG_INFINITY => -1 * (100 ** 100 ** 100);

sub from_spans {
    my $class = shift;
    my %args = validate( @_,
                         { spans =>
                           { type => ARRAYREF,
                             optional => 1,
                           },
                         }
                       );
    my $self = {};
    my $set = Set::Infinite->new();
    $set = $set->union( $_->{set} ) for @{ $args{spans} };
    $self->{set} = $set;
    bless $self, $class;
    return $self;
}

*new = \&from_spans;

sub from_set_and_duration {
    # die "from_set_and_duration() not implemented yet";
    # set => $dt_set, days => 1
    my $class = shift;
    my %args = @_;
    my $set = delete $args{set} || carp "from_set_and_duration needs a set parameter";
    my $duration = delete $args{duration} ||
                   new DateTime::Duration( %args );
    my $end_set = $set->add_duration( $duration );
    return $class->from_sets( start_set => $set, 
                              end_set =>   $end_set );
}

sub from_sets {
    my $class = shift;
    my %args = validate( @_,
                         { start_set =>
                           { can => 'union',
                             optional => 0,
                           },
                           end_set =>
                           { can => 'union',
                             optional => 0,
                           },
                         }
                       );
    my $self;
    $self->{set} = $args{start_set}->{set}->until( 
                   $args{end_set}->{set} );
    bless $self, $class;
    return $self;
}

sub empty_set {
    my $class = shift;

    return bless { set => Set::Infinite->new }, $class;
}

sub clone { 
    bless { 
        set => $_[0]->{set}->copy,
        }, ref $_[0];
}

# iterator() doesn't do much yet.
# This might change as the API gets more complex.
sub iterator {
    return $_[0]->clone;
}

# next() gets the next element from an iterator()
sub next {
    my ($self) = shift;

    # TODO: this is fixing an error from elsewhere
    # - find out what's going on! (with "sunset.pl")
    return undef unless defined $self->{set};

    my ($head, $tail) = $self->{set}->first;
    $self->{set} = $tail;
    return $head unless ref $head;
    my $return = {
        set => $head,
    };
    bless $return, 'DateTime::Span';
    return $return;
}

# Set::Infinite methods

sub intersection {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    $tmp->{set} = $set1->{set}->intersection( $set2->{set} );
    return $tmp;
}

sub intersects {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    return $set1->{set}->intersects( $set2->{set} );
}

sub contains {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    return $set1->{set}->contains( $set2->{set} );
}

sub union {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    $tmp->{set} = $set1->{set}->union( $set2->{set} );
    return $tmp;
}

sub complement {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    if (defined $set2) {
        $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
        $tmp->{set} = $set1->{set}->complement( $set2->{set} );
    }
    else {
        $tmp->{set} = $set1->{set}->complement;
    }
    return $tmp;
}

sub min { 
    my $tmp = $_[0]->{set}->min;
    ref($tmp) ? $tmp->clone : $tmp; 
}

sub max { 
    my $tmp = $_[0]->{set}->max;
    ref($tmp) ? $tmp->clone : $tmp; 
}

# returns a DateTime::Span
sub span { 
  my $set = $_[0]->{set}->span;
  my $self = { set => $set };
  bless $self, 'DateTime::Span';
  return $set;
}

# returns a DateTime::Duration
sub duration { my $dur = $_[0]->{set}->size; defined $dur ? $dur : INFINITY }
*size = \&duration;

# unsupported Set::Infinite methods

sub offset { die "offset() not supported"; }
sub quantize { die "quantize() not supported"; }

1;

__END__

=head1 NAME

DateTime::SpanSet - set of DateTime spans

=head1 SYNOPSIS

    $set1 = DateTime::SpanSet->from_spans( spans => [ $dt_span, $dt_span ] );

    $set = $set1->union( $set2 );         # like "OR", "insert", "both"
    $set = $set1->complement( $set2 );    # like "delete", "remove"
    $set = $set1->intersection( $set2 );  # like "AND", "while"
    $set = $set1->complement;             # like "NOT", "negate", "invert"

    if ( $set1->intersects( $set2 ) ) { ...  # like "touches", "interferes"
    if ( $set1->contains( $set2 ) ) { ...    # like "is-fully-inside"

    # data extraction 
    $date = $set1->min;           # first date of the set
    $date = $set1->max;           # last date of the set

    $iter = $set1->iterator;
    while ( $dt = $iter->next ) {
        # $dt is a DateTime::Span
        print $dt->start->ymd;   # first date of span
        print $dt->end->ymd;     # last date of span
    };

=head1 DESCRIPTION

DateTime::SpanSet is a class that represents sets of datetime spans.
An example would be a recurring meeting that occurs from 13:00-15:00
every Friday.

=head1 METHODS

=over 4

=item * from_spans

Creates a new span set from one or more C<DateTime::Span> objects.

   $dates = DateTime::SpanSet->from_spans( spans => [ $dt_span ] );

=item * from_set_and_duration

Creates a new span set from one or more C<DateTime::Set> objects and a
duration.

The duration can be a C<DateTime::Duration> object, or the parameters
to create a new C<DateTime::Duration> object, such as "days",
"months", etc.

   $dates = DateTime::SpanSet->from_set_and_duration( set => $dt_set, days => 1 );

=item * from_sets

Creates a new span set from two C<DateTime::Set> objects.

One set defines the I<starting dates>, and the other defines the I<end
dates>.

   $dates = DateTime::SpanSet->from_sets( start_set => $dt_set1, end_set => $dt_set2 );

The spans have the starting date C<closed>, and the end date C<open>,
like in C<[$dt1, $dt2)>.

If an end date comes without a starting date before it, then it
defines a span like C<(-inf, $dt)>.

If a starting date comes without an end date after it, then it defines
a span like C<[$dt, inf)>.

=item * empty_set

Creates a new empty set.

=item * min / max

First or last dates in the set.  These methods may return C<undef> if
the set is empty.  It is also possible that these methods may return a
scalar containing infinity or negative infinity.

=item * duration

The total size of the set, as a C<DateTime::Duration> object, or as a
scalar containing infinity.

Also available as C<size()>.

=item * span

The total span of the set, as a C<DateTime::Span> object.

=item * union / intersection / complement

Set operations may be performed not only with C<DateTime::SpanSet>
objects, but also with C<DateTime::Set> and C<DateTime::Span> objects.
These set operations always return a C<DateTime::SpanSet> object.

    $set = $set1->union( $set2 );         # like "OR", "insert", "both"
    $set = $set1->complement( $set2 );    # like "delete", "remove"
    $set = $set1->intersection( $set2 );  # like "AND", "while"
    $set = $set1->complement;             # like "NOT", "negate", "invert"

=item intersects / contains

These set functions return a boolean value.

    if ( $set1->intersects( $set2 ) ) { ...  # like "touches", "interferes"
    if ( $set1->contains( $set2 ) ) { ...    # like "is-fully-inside"

=item * iterator / next

This method can be used to iterate over the date-spans in a set.

    $iter = $set1->iterator;
    while ( $dt = $iter->next ) {
        # $dt is a DateTime::Span
        print $dt->min->ymd;   # first date of span
        print $dt->max->ymd;   # last date of span
    }

The C<next()> returns C<undef> when there are no more spans in the
iterator.  Obviously, if a span set is specified as a recurrence and
has no fixed end, then it may never stop returning spans.  User
beware!

=head1 SUPPORT

Support is offered through the C<datetime@perl.org> mailing list.

Please report bugs using rt.cpan.org

=head1 AUTHOR

Flavio Soibelmann Glock <fglock@pucrs.br>

The API was developed together with Dave Rolsky and the DateTime Community.

=head1 COPYRIGHT

Copyright (c) 2003 Flavio Soibelmann Glock. All rights reserved.
This program is free software; you can distribute it and/or
modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file
included with this module.

=head1 SEE ALSO

Set::Infinite

For details on the Perl DateTime Suite project please see
L<http://datetime.perl.org>.

=cut

