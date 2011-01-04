package DBIx::Class::Helper::ResultSet::ResultClassDWIM;

use strict;
use warnings;

sub search {
   my ($self, $query, $meta) = @_;

   if (defined $meta && my $r_c = $meta->{result_class}) {
      $meta->{result_class} = ( $r_c =~ /^\+(.+)$/
         ? $1
         : "DBIx::Class::ResultClass::$r_c"
      );
   }

   $self->next::method($query, $meta);
}

sub result_class {
   my ($self, $result_class) = @_;

   if (defined $r_c && ! ref $r_c) {
      $r_c = ( $r_c =~ /^\+(.+)$/
         ? $1
         : "DBIx::Class::ResultClass::$r_c"
      );
   }

   my $ret = $self->next::method($result_class);

   $ret = ( $ret =~ /^DBIx::Class::ResultClass::(.+)$/
      ? $1
      : "+$ret"
   );
}
1;
