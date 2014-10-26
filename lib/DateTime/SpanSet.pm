# Copyright (c) 2003 Flavio Soibelmann Glock. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package DateTime::SpanSet;

use strict;

use DateTime::Set;
# use DateTime::SpanSet;

use Carp;
use Params::Validate qw( validate SCALAR BOOLEAN OBJECT CODEREF ARRAYREF );
use vars qw( $VERSION );

use constant INFINITY     =>       100 ** 100 ** 100 ;
use constant NEG_INFINITY => -1 * (100 ** 100 ** 100);
$VERSION = $DateTime::Set::VERSION;

sub iterate {
    my ( $self, $callback ) = @_;
    my $class = ref( $self );
    my $return = $class->empty_set;
    $return->{set} = $self->{set}->iterate(
        sub {
            my $span = bless { set => $_[0] }, 'DateTime::Span';
            $callback->( $span->clone );
            $span = $span->{set} 
                if UNIVERSAL::can( $span, 'union' );
            return $span;
        }
    );
    $return;
}

sub set_time_zone {
    my ( $self, $tz ) = @_;

    # TODO - use iterate() instead 

    my $result = $self->{set}->iterate( 
        sub {
            my %tmp = %{ $_[0]->{list}[0] };
            $tmp{a} = $tmp{a}->clone->set_time_zone( $tz ) if ref $tmp{a};
            $tmp{b} = $tmp{b}->clone->set_time_zone( $tz ) if ref $tmp{b};
            \%tmp;
        }
    );

    ### this code enables 'subroutine method' behaviour
    # $self->{set} = $result;
    # return $self;

    ### this code enables 'function method' behaviour
    my $set = $self->clone;
    $set->{set} = $result;
    return $set;
}

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
    my $set = Set::Infinite::_recurrence->new();
    $set = $set->union( $_->{set} ) for @{ $args{spans} };
    $self->{set} = $set;
    bless $self, $class;
    return $self;
}

sub from_set_and_duration {
    # die "from_set_and_duration() not implemented yet";
    # set => $dt_set, days => 1
    my $class = shift;
    my %args = @_;
    my $set = delete $args{set} || carp "from_set_and_duration needs a set parameter";
    my $duration = delete $args{duration} ||
                   new DateTime::Duration( %args );
    my $end_set = $set->clone->add_duration( $duration );
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

sub start_set {
    my $return = DateTime::Set->empty_set;
    $return->{set} = $_[0]->{set}->start_set;
    $return;
}

sub end_set {
    my $return = DateTime::Set->empty_set;
    $return->{set} = $_[0]->{set}->end_set;
    $return;
}

sub empty_set {
    my $class = shift;

    return bless { set => Set::Infinite::_recurrence->new }, $class;
}

sub clone { 
    bless { 
        set => $_[0]->{set}->copy,
        }, ref $_[0];
}


sub iterator {
    my $self = shift;

    my %args = @_;
    my $span;
    $span = delete $args{span};
    $span = DateTime::Span->new( %args ) if %args;

    return $self->intersection( $span ) if $span;
    return $self->clone;
}


# next() gets the next element from an iterator()
sub next {
    my ($self) = shift;

    # TODO: this is fixing an error from elsewhere
    # - find out what's going on! (with "sunset.pl")
    return undef unless ref $self->{set};

    if ( @_ )
    {
        my $max = $_[0];
        my $open_end = 0;
        ( $max, $open_end ) = $max->{set}->max_a if UNIVERSAL::can( $max, 'union' );
        my $span;
        $span = $open_end ?
                DateTime::Span->from_datetimes( start => $max ) :
                DateTime::Span->from_datetimes( after => $max );
        return $self->intersection( $span )->next;
    }

    my ($head, $tail) = $self->{set}->first;
    $self->{set} = $tail;
    return $head unless ref $head;
    my $return = {
        set => $head,
    };
    bless $return, 'DateTime::Span';
    return $return;
}

# previous() gets the last element from an iterator()
sub previous {
    my ($self) = shift;

    return undef unless ref $self->{set};

    if ( @_ )
    {
        my $min = $_[0];
        my $open_start = 0;
        ( $min, $open_start ) = $min->{set}->min_a if UNIVERSAL::can( $min, 'union' );
        my $span;
        $span = $open_start ?
                DateTime::Span->from_datetimes( end => $min ) :
                DateTime::Span->from_datetimes( before => $min );
        return $self->intersection( $span )->previous;
    }

    my ($head, $tail) = $self->{set}->last;
    $self->{set} = $tail;
    return $head unless ref $head;
    my $return = {
        set => $head,
    };
    bless $return, 'DateTime::Span';
    return $return;
}

sub as_list {
    my $self = shift;
    return undef unless ref( $self->{set} );

    my %args = @_;
    my $span;
    $span = delete $args{span};
    $span = DateTime::Span->new( %args ) if %args;

    my $set = $self->clone;
    $set = $set->intersection( $span ) if $span;

    # Note: removing this line means we may end up in an infinite loop!
    return undef if $set->{set}->is_too_complex;  # undef = no begin/end

    # return if $set->{set}->is_null;  # nothing = empty
    my @result;
    # we should extract _copies_ of the set elements,
    # such that the user can't modify the set indirectly

    my $iter = $set->iterator;
    while ( my $dt = $iter->next )
    {
        push @result, $dt
            if ref( $dt );   # we don't want to return INFINITY value
    };

    return @result;
}

# Set::Infinite methods

sub intersection {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->empty_set();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    $tmp->{set} = $set1->{set}->intersection( $set2->{set} );
    return $tmp;
}

sub intersects {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->empty_set();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    return $set1->{set}->intersects( $set2->{set} );
}

sub contains {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->empty_set();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    return $set1->{set}->contains( $set2->{set} );
}

sub union {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->empty_set();
    $set2 = DateTime::Set->from_datetimes( dates => [ $set2 ] ) unless $set2->can( 'union' );
    $tmp->{set} = $set1->{set}->union( $set2->{set} );
    return $tmp;
}

sub complement {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->empty_set();
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
    my $self = bless { set => $set }, 'DateTime::Span';
    return $self;
}

# returns a DateTime::Duration
sub duration { 
    my $dur; 
    eval { $dur = $_[0]->{set}->size };
    return $dur if defined $dur;
    $@ = undef;  # clear the eval() error message
    return INFINITY;
}
*size = \&duration;

1;

__END__

=head1 NAME

DateTime::SpanSet - set of DateTime spans

=head1 SYNOPSIS

    $spanset = DateTime::SpanSet->from_spans( spans => [ $dt_span, $dt_span ] );

    $set = $spanset->union( $set2 );         # like "OR", "insert", "both"
    $set = $spanset->complement( $set2 );    # like "delete", "remove"
    $set = $spanset->intersection( $set2 );  # like "AND", "while"
    $set = $spanset->complement;             # like "NOT", "negate", "invert"

    if ( $spanset->intersects( $set2 ) ) { ...  # like "touches", "interferes"
    if ( $spanset->contains( $set2 ) ) { ...    # like "is-fully-inside"

    # data extraction 
    $date = $spanset->min;           # first date of the set
    $date = $spanset->max;           # last date of the set

    $iter = $spanset->iterator;
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

   $spanset = DateTime::SpanSet->from_spans( spans => [ $dt_span ] );

=item * from_set_and_duration

Creates a new span set from one or more C<DateTime::Set> objects and a
duration.

The duration can be a C<DateTime::Duration> object, or the parameters
to create a new C<DateTime::Duration> object, such as "days",
"months", etc.

   $spanset =
       DateTime::SpanSet->from_set_and_duration
           ( set => $dt_set, days => 1 );

=item * from_sets

Creates a new span set from two C<DateTime::Set> objects.

One set defines the I<starting dates>, and the other defines the I<end
dates>.

   $spanset =
       DateTime::SpanSet->from_sets
           ( start_set => $dt_set1, end_set => $dt_set2 );

The spans have the starting date C<closed>, and the end date C<open>,
like in C<[$dt1, $dt2)>.

If an end date comes without a starting date before it, then it
defines a span like C<(-inf, $dt)>.

If a starting date comes without an end date after it, then it defines
a span like C<[$dt, inf)>.

=item * empty_set

Creates a new empty set.

=item * clone

This object method returns a replica of the given object.

=item * set_time_zone( $tz )

This method accepts either a time zone object or a string that can be
passed as the "name" parameter to C<< DateTime::TimeZone->new() >>.
If the new time zone's offset is different from the old time zone,
then the I<local> time is adjusted accordingly.

If the old time zone was a floating time zone, then no adjustments to
the local time are made, except to account for leap seconds.  If the
new time zone is floating, then the I<UTC> time is adjusted in order
to leave the local time untouched.

The method returns a new object.

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

=item * previous / next 

  my $span = $set->next( $dt );

  my $span = $set->previous( $dt );

These methods are used to find a set member relative to a given
datetime or span.

The return value may be C<undef> if there is no matching
span in the set.


=item * as_list

Returns a list of C<DateTime::Span> objects.

  my @dt = $set->as_list( span => $span );

Just as with the C<iterator()> method, the C<as_list()> method can be
limited by a span.

If a set is specified as a recurrence and has no
fixed begin and end datetimes, then C<as_list> will return C<undef>
unless you limit it with a span.  Please note that this is explicitly
not an empty list, since an empty list is a valid return value for
empty sets!

=item * union / intersection / complement

Set operations may be performed not only with C<DateTime::SpanSet>
objects, but also with C<DateTime>, C<DateTime::Set> and
C<DateTime::Span> objects.  These set operations always return a
C<DateTime::SpanSet> object.

    $set = $spanset->union( $set2 );         # like "OR", "insert", "both"
    $set = $spanset->complement( $set2 );    # like "delete", "remove"
    $set = $spanset->intersection( $set2 );  # like "AND", "while"
    $set = $spanset->complement;             # like "NOT", "negate", "invert"

=item * intersects / contains

These set functions return a boolean value.

    if ( $spanset->intersects( $set2 ) ) { ...  # like "touches", "interferes"
    if ( $spanset->contains( $dt ) ) { ...    # like "is-fully-inside"

These methods can accept a C<DateTime>, C<DateTime::Set>,
C<DateTime::Span>, or C<DateTime::SpanSet> object as an argument.

=item * iterator / next / previous

This method can be used to iterate over the spans in a set.

    $iter = $spanset->iterator;
    while ( $dt = $iter->next ) {
        # $dt is a DateTime::Span
        print $dt->min->ymd;   # first date of span
        print $dt->max->ymd;   # last date of span
    }

The boundaries of the iterator can be limited by passing it a C<span>
parameter.  This should be a C<DateTime::Span> object which delimits
the iterator's boundaries.  Optionally, instead of passing an object,
you can pass any parameters that would work for one of the
C<DateTime::Span> class's constructors, and an object will be created
for you.

Obviously, if the span you specify does is not restricted both at the
start and end, then your iterator may iterate forever, depending on
the nature of your set.  User beware!

The C<next()> or C<previous()> methods will return C<undef> 
when there are no more spans in the iterator.

=item * start_set

=item * end_set

These methods do the inverse of the C<from_sets> method:

C<start_set> retrieves a DateTime::Set with the start datetime of each span.

C<end_set> retrieves a DateTime::Set with the end datetime of each span.

=item * iterate

I<Experimental method - subject to change.>

This function apply a callback subroutine to all elements of a set
and returns the resulting set.

The parameter C<$_[0]> to the callback subroutine is a C<DateTime::Span>
object.

    [TODO - fix example]

    sub callback {
        $_[0]->add( hours => 1 );
    }

    # $set2 elements are one hour after $set elements, and
    # $set is unchanged
    $set2 = $set->iterate( \&callback );

If the callback returns C<undef>, the datetime is removed from the set:

    sub remove_sundays {
        $_[0] unless $_[0]->start->day_of_week == 7;
    }

The callback can be used to postpone or anticipate
events which collide with datetimes in another set:

    [TODO - fix example]

    sub after_holiday {
        $_[0]->add( days => 1 ) while $holidays->contains( $_[0] );
    }

The callback return value is expected to be within the span of the
C<previous> and the C<next> element in the original set.

For example: given the set C<[ 2001, 2010, 2015 ]>,
the callback result for the value C<2010> is expected to be
within the span C<[ 2001 .. 2015 ]>.

The callback subroutine may not be called immediately.
Don't count on subroutine side-effects. For example,
a C<print> inside the subroutine may happen later than you expect.

=back

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

