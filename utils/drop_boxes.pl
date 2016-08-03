#! /usr/bin/perl -w

use strict;
use warnings;

use Config::IniFiles;


foreach my $fn ( @ARGV ) {
  my %ini;
  tie %ini, "Config::IniFiles", ( -file => $fn );
  foreach my $sect ( keys %ini ) {
    if (
      $ini{ $sect }->{ visual_name }
      and $ini{ $sect }->{ visual_name } eq 'physics\box\box_wood_01'
      and $ini{ $sect }->{ custom_data }
    ) {
      my $cd = join( "\n", @{ $ini{ $sect }->{ custom_data } } );
      if ( $cd =~ "drop_box" ) {
        printf(
          "{ \"%s\", %u },\n",
          $ini{ $sect }->{ name }, , $ini{ $sect }->{ spawn_id }
        );
      }
    }
  }
}
