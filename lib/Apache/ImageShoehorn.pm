{

=head1 NAME

Apache::ImageShoehorn - mod_perl wrapper for Image::Shoehorn

=head1 SYNOPSIS

  <Directory /path/to/some/directory/with/images>
   SetHandler	perl-script
   PerlHandler	Apache::ImageShoehorn

   PerlSetVar   ScaledDir       /path/to/some/dir

   PerlSetVar	SetScaleSmall	25%
   PerlSetVar	SetScaleMedium	50%
   PerlSetVar	SetScaleLarge	75%
   PerlSetVar	SetScaleThumb	x50

   <FilesMatch "\.html$">
    # Do something with HTML files here
   </FilesMatch>
  </Directory>

  #

  http://www.foo.com/images/bar.jpg?scale=medium

=head1 DESCRIPTION

Apache mod_perl wrapper for Image::Shoehorn.

=head1 CONFIG DIRECTIVES

=over

=item *

ScaledDir          I<string>

A path on the filesystem where the handler will save images that have been scaled

Remember, this directory needs to be writable by whatever user is running the http daemon.

=item *

SetScaleI<Name>    I<string>

Define the names and dimensions of scaled images. I<name> will be converted to lower-case and compared with the I<scale> CGI query parameter. If no matching config directive is located, the handler will return DECLINED.

If there are multiple SetScale directives then they will be processed, if necessary, during the handler's cleanup stage.

If a scaled image already exists, it will not be rescaled until the lastmodified time for the source file is greater than that of the scaled version.

Valid dimensions are identical as those listed in I<Image::Shoehorn>.

=back

=cut

package Apache::ImageShoehorn;
use strict;

$Apache::ImageShoehorn::VERSION = '0.9';

use Apache;
use Apache::Constants qw (:common);
use Apache::File;
use Apache::Log;

use Image::Shoehorn 1.1;

my %TYPES   = ();
my @FORMATS = ();

sub handler {
    my $apache = shift;

    unless (&_valid_type($apache)) {
      return DECLINED;
    }

    #

    my %params = ($apache->method() eq "POST") ? $apache->content() : $apache->args();
    my $sname  = $params{"scale"};

    my $scale = $apache->dir_config("SetScale".(ucfirst $sname));
    if (! $scale) { return DECLINED; }

    #

    my $source = $apache->filename();
    my $mtime  = (stat($source))[9];

    #

    my $scaled = &_scalepath($apache,[$source,$sname]);

    if (! &_modified([$mtime,$scaled])) {
      $apache->register_cleanup(sub { &_scaleall($apache,undef,$source,$mtime); });
      return &_send($apache,{path=>$scaled});
    }

    #

    my $shoehorn = &_shoehorn($apache);

    if (! $shoehorn) {
      $apache->log()->error("Unable to create Image::Shoehorn object :".
			    Image::Shoehorn->last_error());
      return SERVER_ERROR;
    }

    #

    my ($imgs,$err) = &_scale($shoehorn,$source,$sname,$scale);

    if (! $imgs) {
	$apache->log()->error("Unable to scale : $err");
	return NOT_FOUND;
    }

    #
    
    $apache->register_cleanup(sub { &_scaleall($apache,$shoehorn,$source,$mtime); });

    return &_send($apache,$imgs->{$sname});
}

sub _shoehorn {
  my $apache = shift;
  return Image::Shoehorn->new({
			       tmpdir  => $apache->dir_config("ScaledDir"),
			       cleanup => sub {},
			      });
}

sub _send {
  my $apache = shift;
  my $image  = shift;

  my $fh = Apache::File->new($image->{'path'});

  if (! $fh) {
    $apache->log()->error("Unable to create filehandle, $!");
    return SERVER_ERROR;
  }

  $apache->content_type($apache->content_type());
  $apache->send_http_header();
  $apache->send_fd($fh);
  
  return OK;
}

sub _scale {
  my $shoehorn = shift;
  my $source   = shift;
  my $name     = shift;
  my $scale    = shift;

  my $imgs = $shoehorn->import({
				source => $source,
				scale  => { $name => $scale },
			       }) || return (0,Image::Shoehorn->last_error());

  return ($imgs,undef);
}

sub _scaleall {
  my $apache   = shift;
  my $shoehorn = shift;
  my $source   = shift;
  my $mtime    = shift;

  my %scales = ();

  foreach my $var (keys %{$apache->dir_config()}) {
    $var =~ /^SetScale(.*)/;
    next unless $1;
    
    my $name   = lc($1);
    my $scaled = &_scalepath($apache,[$source,$name]);

    next unless (&_modified([$mtime,$scaled]));
    $scales{$name} = $apache->dir_config($var);
  }

  if (keys %scales) {

    if (ref($shoehorn) ne "Image::Shoehorn") {
      $shoehorn = &_shoehorn($apache);
    }
    
    if (! $shoehorn) {
      $apache->log()->error(Image::Shoehorn->last_error());
      return 0;
    }
    
    if (! $shoehorn->import({
			     source => $source,
			     scale  => \%scales,
			    })) {

      $apache->log()->error(Image::Shoehorn->last_error());
      return 0;
    }
  }

  return 1;
}

sub _valid_type {
  my $apache = shift;

  $apache->content_type() =~ /^(.*)\/(.*)$/;

  if (! $2) { return 0; }

  if (exists($TYPES{$2})) {
    return $TYPES{$2};
  }

  if (! @FORMATS) {
    @FORMATS = Image::Magick->QueryFormat();
  }
  
  $TYPES{$2} = grep(/^($2)$/,@FORMATS);
  return $TYPES{$2};
}

sub _scalepath {
  my $apache = shift;

  my $scaled = Image::Shoehorn->scaled_name($_[0]);
  $scaled    = $apache->dir_config("ScaledDir")."/$scaled";

  return $scaled;
}

sub _modified {
  my $args = shift;

  # $args->[0] - the mtime for the source file
  # $args->[1] - the path for the scale file

  if (! -f $args->[1]) { return 1; }

  if ($args->[0] > (stat($args->[1]))[9]) {
    return 1;
  }

  return 0;
}

=head1 VERSION

0.9

=head1 DATE

June 12, 2002

=head1 AUTHOR

Aaron Straup Cope

=head1 TO DO

=over

=item *

Add hooks to allow for images to be be converted from one format to another. For example, a directory full of PhotoCD images would be sent to the browser as JPEGs.

=item *

Add hooks to store global I<TYPES> and I<FORMATS> data in a global hash keyed by the handler's location.

=back

=head1 SEE ALSO 

L<Image::Shoehorn>

=head1 LICENSE

Copyright (c) 2002 Aaron Straup Cope. All Rights Reserved.

This is free software, you may use it and distribute it under the same terms as Perl itself.

=cut

return 1;

}
