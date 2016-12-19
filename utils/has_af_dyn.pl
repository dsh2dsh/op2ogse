#! /usr/bin/perl -w

use strict;
use warnings;


foreach (<>) {
  chomp;
  my ( $sect, $left ) = split( /\s+/, $_, 2 );
  printf( "%-33s %s\n", $sect, $left );
  next if $sect =~ /\.af_bio$/;
  for ( my $i = 1; $i <= 5; $i++ ) {
    printf( "%-33s %s\n", sprintf( "%s_dyn%dd", $sect, $i ), $left );
    printf( "%-33s %s\n", sprintf( "%s_dyn%dd.af_bio", $sect, $i ), $left );
  }
}
