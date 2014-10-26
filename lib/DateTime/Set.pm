# Copyright (c) 2003 Flavio Soibelmann Glock. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package DateTime::Set;

use strict;

use Params::Validate qw( validate SCALAR BOOLEAN OBJECT CODEREF ARRAYREF );
use Set::Infinite '0.44';
$Set::Infinite::PRETTY_PRINT = 1;   # enable Set::Infinite debug

use vars qw( @ISA $VERSION );

$VERSION = '0.00_13';

use constant INFINITY     =>       100 ** 100 ** 100 ;
use constant NEG_INFINITY => -1 * (100 ** 100 ** 100);


# _add_callback( $set_infinite, $datetime_duration )
# Internal function
#
# Adds a value to a DateTime in a set.
#
# this is an internal callback - it is not an object method!
# Used by: add()
#
sub _add_callback {
    my $set = shift;   # $set is a Set::Infinite object
    my $dt = shift;    # $dt is a DateTime::Duration
    my $min = $set->min;
    if ( ref($min) ) {
        $min = $min->clone;
        $min->add_duration( $dt ) if ref($min);
    }
    my $result = $set->new( $min );
    return $result;
}; 

sub add {
    my ($self, %parm) = @_;
    my $dt;
    if (exists $parm{duration}) {
        $dt = $parm{duration}->clone;
    }
    else {
        $dt = new DateTime::Duration( %parm );
    }
    my $result = $self->{set}->iterate( \&_add_callback, $dt );

    ### this code would enable 'subroutine method' behaviour
    # $self->{set} = $result;
    # return $self;

    ### this code enables 'function method' behaviour
    my $set = $self->clone;
    $set->{set} = $result;
    return $set;
}

# note: the constructor must clone its DateTime parameters, such that
# the set elements become immutable
sub new {
    my $class = shift;
    my %args = validate( @_,
                         { start =>
                           { type => OBJECT,
                             optional => 1,
                           },
                           end =>
                           { type => OBJECT,
                             optional => 1,
                           },
                           recurrence =>
                           { type => CODEREF,
                             optional => 1,
                           },
                           dates => 
                           { type => ARRAYREF,
                             optional => 1,
                           },
                         }
                       );
    my $self = {};
    if (exists $args{dates}) {
        $self->{set} = Set::Infinite->new;
        # warn "new: inserting @{ $args{dates} }";
        for( @{ $args{dates} } ) {
            # warn "new: inserting ".$_->ymd;
            $self->{set} = $self->{set}->union( $_->clone );
        }
    }
    elsif (exists $args{recurrence}) {
        # Set::Infinity->iterate() builds a "set-function" with a callback:
        my $start = ( exists $args{start} ) ? $args{start} : NEG_INFINITY;
        my $end =   ( exists $args{end} )   ? $args{end}   : INFINITY;
        $start = $start->clone if ref($start);
        $end =   $end->clone   if ref($end);
        my $tmp_set = Set::Infinite->new( $start, $end );
        $self->{set} = _recurrence_callback( $tmp_set, $args{recurrence} );  
    }
    else {
        $self->{set} = Set::Infinite->new;
    }
    bless $self, $class;
    return $self;
}

sub clone { 
    bless { 
        set => $_[0]->{set}->copy,
        }, ref $_[0];
}

# _recurrence_callback( $set_infinite, \&callback )
# Internal function
#
# Generates "recurrences" from a callback.
# These recurrences are simple lists of dates.
#
# this is an internal callback - it is not an object method!
# Used by: new( recurrence => )
#
# The recurrence generation is based on an idea from Dave Rolsky.
#
sub _recurrence_callback {
    # warn "_recurrence args: @_";
    # note: $self is a Set::Infinite object
    my ( $self, $callback ) = @_;    

    # test for the special case when we have an infinite recurrence

    if ($self->min == NEG_INFINITY ||
        $self->max == INFINITY) {
        # warn "_recurrence called with inf argument";
        return NEG_INFINITY if $self->min == NEG_INFINITY && $self->max == NEG_INFINITY;
        return INFINITY if $self->min == INFINITY && $self->max == INFINITY;
        # return an internal "_function", such that we can 
        # backtrack and solve the equation later.
        $self = $self->copy;
        my $func = $self->_function( 'iterate', 
            sub {
                _recurrence_callback( $_[0], $callback );
            }
        );

        # -- begin hack

        # This code will be removed, as soon as Set::Infinite can deal directly with this type of set generation.
        # Since this is a Set::Infinite custom function, the iterator will need some help.
        # We are setting up the first() cache directly,
        # because Set::Infinite has no hint of how to do it.

        if ($self->min == INFINITY || $self->min == NEG_INFINITY) {
            # warn "RECURR: start in ".$self->min;
            $func->{first} = [ $self->new( $self->min ), $self ];
        }
        else {
            my $this = $func->min;
            my $next = &$callback($this->clone);
            # warn "RECURR: preparing first: ".$this->ymd." ; ".$next->ymd;
            my $next_set = $self->intersection( $next->clone, INFINITY );
            # warn "next_set min is ".$next_set->min->ymd;
            my @first = ( 
                $self->new( $this->clone ), 
                $next_set->_function( 'iterate',
                    sub {
                        _recurrence_callback( $_[0], $callback );
                    } ) );
            # warn "RECURR: preparing first: $this ; $next; got @first";
            $func->{first} = \@first;
        }
        # -- end hack

        # warn "func parent is ". $func->{first}[1]{parent}{list}[0]{a}->ymd;
        return $func;
    }

    # this is a finite recurrence - generate it.
    # warn "RECURR: FINITE recurrence";
    my $min = $self->min;
    return unless defined $min;
    $min = $min->clone->subtract( seconds => 1 );
    my $max = $self->max;
    # warn "_recurrence_callback called with ".$min->ymd."..".$max->ymd;
    my $result = $self->new;
    my $subset;
    do {
        # warn " generate from ".$min->ymd;
        $min = &$callback( $min );
        # warn " generate got ".$min->ymd;
        $result = $result->union( $min->clone );
    } while ( $min <= $max );
    return $result;
}


# iterator() doesn't do much yet.
# This might change as the API gets more complex.
sub iterator {
    return $_[0]->clone;
}

# next() gets the next element from an iterator()
sub next {
    my ($self) = shift;
    my ($head, $tail) = $self->{set}->first;
    $self->{set} = $tail;
    return $head->min;
}

# Set::Infinite methods

sub intersection {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = $class->new( dates => [ $set2 ] ) unless $set2->isa( $class );
    $tmp->{set} = $set1->{set}->intersection( $set2->{set} );
    return $tmp;
}

sub intersects {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = $class->new( dates => [ $set2 ] ) unless $set2->isa( $class );
    return $set1->{set}->intersects( $set2->{set} );
}

sub contains {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = $class->new( dates => [ $set2 ] ) unless $set2->isa( $class );
    return $set1->{set}->contains( $set2->{set} );
}

sub union {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    $set2 = $class->new( dates => [ $set2 ] ) unless $set2->isa( $class );
    $tmp->{set} = $set1->{set}->union( $set2->{set} );
    return $tmp;
}

sub complement {
    my ($set1, $set2) = @_;
    my $class = ref($set1);
    my $tmp = $class->new();
    if (defined $set2) {
        $set2 = $class->new( dates => [ $set2 ] ) unless $set2->isa( $class );
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

# unsupported Set::Infinite methods

sub span { die "span() not supported - would generate a span!"; }
sub size { die "size() not supported - would be zero!"; }
sub offset { die "offset() not supported"; }
sub quantize { die "quantize() not supported"; }

1;

__END__

=head1 NAME

DateTime::Set - Date/time sets math

=head1 SYNOPSIS

NOTE: this is just an example of how the API will look like when
this module is finished.

    use DateTime;
    use DateTime::Set;

    $date1 = DateTime->new( year => 2002, month => 3, day => 11 );
    $set1 = DateTime::Set->new( dates => [ $date1 ] );
    #  set1 = 2002-03-11

    $date2 = DateTime->new( year => 2003, month => 4, day => 12 );
    $set2 = DateTime::Set->new( dates => [ $date1, $date2 ] );
    #  set2 = 2002-03-11, and 2003-04-12

    # a 'monthly' recurrence:
    $set = DateTime::Set->new( 
        recurrence => sub {
            $_[0]->truncate( to => 'month' )->add( months => 1 )
        },
        start => $date1,    # optional
        end => $date2,      # optional
    );

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
        print $dt->ymd;
    };

=head1 DESCRIPTION

DateTime::Set is a module for date/time sets. It allows you to generate
groups of dates, like "every wednesday", and then find all the dates
matching that pattern, within a time range.

=head1 ERROR HANDLING

A method will return C<undef> if it can't find a suitable 
representation for its result, such as when trying to 
C<list()> a too complex set.

Programs that expect to generate empty sets or complex sets
should check for the C<undef> return value when extracting data.

Set elements must be either a C<DateTime> or a C<+/- Infinity> value.
Scalar values, including date strings, are not expected and
might cause strange results.

=head1 METHODS

=over 4

=item * new 

Generates a new set. The set can be generated from a list of dates, or from a "recurrence" subroutine.

From a list of dates:

   $dates = DateTime::Set->new( dates => [ $dt1, $dt2, $dt3 ] );

From a recurrence:

    $months = DateTime::Set->new( 
        start => $today, 
        end => $next_year,
        recurrence => sub { $_[0]->truncate( to => 'month' )->add( months => 1 ) }, 
    );

The start and end parameters are optional.

=item * add

    $new_set = $set->add( year => 1 );

    $dtd = new DateTime::Duration( year => 1 );
    $new_set = $set->add( duration => $dtd );

This function method adds a value to a DateTime set, generating a new set.

It moves the whole set values ahead or back in time.

Example:

    $meetings_2004 = $meetings_2003->add( year => 1 );

See C<DateTime::add()> for full syntax description.

=item * iterator / next

    $iter = $set1->iterator;
    while ( $dt = $iter->next ) {
        print $dt->ymd;
    };

Extract dates from a set. 

next() returns undef when there are no more dates.

=back

=head1 SUPPORT

Support is offered through the C<datetime@perl.org> mailing list.

Please report bugs using rt.cpan.org

=head1 AUTHOR

Flavio Soibelmann Glock <fglock@pucrs.br>

=head1 COPYRIGHT

Copyright (c) 2003 Flavio Soibelmann Glock. All rights reserved.
This program is free software; you can distribute it and/or
modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file
included with this module.

=head1 SEE ALSO

Set::Infinite

L<http://datetime.perl.org>.

For details on the Perl DateTime Suite project please see
L<http://perl-date-time.sf.net>.

=cut

