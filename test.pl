use strict;

BEGIN { $| = 1; print "1..3\n"; }

use Image::Shoehorn;
use Data::Dumper;
use Cwd;

my $examples = undef;
my $source   = undef;
my $image    = undef;

if (&t3(&t2(&t1()))) {
  print "Passed all tests.\n";
}

sub t1 {
  $examples = &Cwd::getcwd()."/examples";

  if (! -d $examples) {
    print "Ack! Unable to find the 'examples' dir in the Image-Shoehorn directory.\n";

    print "not ok 1\n";
    return 0;
  }

  $source = "$examples/20020313-scary-easter-monsters.jpg";

  if (! -f $source) {
    print "Ack! Unable to find the 'scary easter monsters' image in the Image-Shoehorn/examples directory.\n";

    print "not ok 1\n";
    return 0;
  }

  print "ok 1\n";
  return 1;
}

sub t2 {
  my $last = shift;

  if (! $last) {
    print "not ok 2\n";
    return 0;
  }

  $image = Image::Shoehorn->new({
				 tmpdir  => $examples,
				 cleanup => \&cleanup,
				});

  if (! $image) {
    print "Ack! Failed to create Image::Shoehorn object:".Image::Shoehorn->last_error()."\n";

    print "not ok 2\n";
    return 0;
  }

  print "ok 2\n";
  return 1;
}

sub t3 {
  my $last = shift;

  if (! $last) {
    print "not ok 3\n";
    return 0;
  }

  my $imgs = $image->import({
			     source     => $source,
			     valid      => [ "png" ],
			     convert    => 1,
			     max_height => 200,
			     scale      => {small=>"25%"},
			    }) || die $image->last_error();

  if (! $imgs) {
    print "Ack! Failed to create $source:".Image::Shoehorn->last_error()."\n";

    print "not ok 3\n";
    return 0;
  }

  print &Dumper($imgs);

  print "ok 3\n";
  return 1;
}

sub cleanup {
  my $imgs = shift;
  print "This is the user-defined cleanup method.\n";
  map { print "Hello $imgs->{$_}->{'path'}\n"; } keys %$imgs;
}
