package Weather::Underground;

use strict;
use vars qw(
	$VERSION @ISA @EXPORT @EXPORT_OK
	$CGI $CGIVAR $MYNAME $DEBUG
	);
use LWP::Simple;
require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '2.06';


# Preloaded methods go here.

sub _debug() {
        my $notice = shift;
        $@ = $notice;
        if ($DEBUG) {
                print "$MYNAME DEBUG NOTE: $notice\n";
                return 1;
                }
        return 0;
        }

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Weather::Underground - Perl extension for retrieving weather information from wunderground.com

=head1 SYNOPSIS

	use Weather::Underground;

	$weather = Weather::Underground->new(
		place   =>      "Montreal, Canada",
		debug           =>      0
		)
		|| die "Error, could not create new weather object: $@\n";

	$arrayref = $weather->getweather()
		|| die "Error, calling getweather() failed: $@\n";

	foreach (@$arrayref) {
		print "MATCH:\n";
		while (($key, $value) = each %{$_}) {
			print "\t$key = $value\n";
			}
		}

=head1 DESCRIPTION

Weather::Underground is a perl module which provides a simple OO interface to retrieving weather data for a geographic location.  It does so by querying wunderground.com and parsing the returned results.

=head1 CONSTRUCTOR

	new(hashref);

new() creates and returns a new Weather::Underground object.

"hashref" is a reference to a hash.

Required keys in the hash:

	place

Optional keys in the hash:

	debug

"place" key should be assigned the value of the geographical place you would like to retrieve the weather information for.  The format of specifying the place really depends on wunderground.com more than it depends on this perl module, however at the time of this writing they accept 'City', 'City, State', 'State', 'State, Country' and 'Country'.

"debug" key should be set to 0 or 1. 0 means no debugging information will be printed, 1 means debug information will be printed.

=head1 METHODS

	getweather();

getweather() is used to initiate the connection to wunderground.com, query their system, and parse the results.

If no results are found, returns undef;

If results are found, returns an array reference.  Each element in the array is a hash reference. Each hash contains information about a place that matched the query;

Each hash contains the following keys:

	place
	(the exact place that was matched)

	celsius
	(the temperature in celsius)

	fahrenheit
	(the temperature in fahrenheit)

	humidity
	(humidity percentage)

	conditions
	(a 1-3 word sentence describing overall conditions, example: 'Partly cloudy')
	

=head1 NOTICE

Your query may result in more than 1 match. Each match is a hash reference added as a new value in the array which getweather() returns the reference to.

=head1 EXAMPLES

Example 1: Print all matching information

	See SYNOPSIS

Example 2: Print the Celsius temperature of the first matching place

        use Weather::Underground;

        $weather = Weather::Underground->new(
                place   =>      "Montreal",
                debug           =>      0
                )
                || die "Error, could not create new weather object: $@\n";

        $arrayref = $weather->getweather()
                || die "Error, calling getweather() failed: $@\n";

	print "The celsius temperature at the first matching place is " . $arrayref->[0]->{celsius} . "\n";

=head1 ERRORS

All methods return something that evaluates to true when successful, or undef when not successful.

If the constructor or a method returns undef, the variable $@ will contain a text string containing the error that occurred.

=head1 AUTHOR

Mina Naguib, webmaster@topfx.com

=cut

#
# GLOBAL Variables Assignments
#

$CGI = 'http://www.wunderground.com/cgi-bin/findweather/getForecast';
$CGIVAR = 'query';
$MYNAME = "Weather::Underground";
$DEBUG = 0;

#
# Public methods
#

sub new() {
	my ($class, %parameters) = @_;
	my $self;
	$DEBUG = $parameters{debug};
	&_debug("Creating a new $MYNAME object");
	if (!$parameters{place}) {
		&_debug("ERROR: Location not specified");
		return undef;
		}
	$self = {
		_place	=>	$parameters{place},
		_url	=>	$CGI . '?' . $CGIVAR . '=' . $parameters{place}
		};
	bless($self, $class);
	return $self;
	}

sub getweather() {
	my ($self) = @_;
	my $document;
	my ($place, $temperature, $scale, $humidity, $conditions);
	my ($fahrenheit, $celsius);
	my $arrayref = [];
	my $counter = 0;
	&_debug("Getting weather info for " . $self->{_place});
	&_debug("Retrieving url " . $self->{_url});
	$document = get($self->{_url});
	if (!$document) {
		&_debug("Could not retrieve HTML document " . $self->{_url});
		return undef;
		}
	#
	# Let's clean up stuff that's there to confuse the parser
	#
	$document =~ s|<b>||g;
	$document =~ s|</b>||g;
	$document =~ s/((?<=\W)[ \t]+)|([ \t]+(?=\W))//g;
	$document =~ s/\n{2,}/\n/g;
	&_debug("I retrieved the following data:\n\n\n\n\n$document\n\n\n\n\n");
	#
	# The first format is to match multiple-listing matches :
	#
	while ($document =~ m|<tr bgcolor=.*?>\n?<td><a\s.*?>([\w\s,]+?)</a></td>\n?<td>\n(\d+)&#176;(\w).*?</td>\n?<td>(\d+)\%</td>\n?<td>.*?</td>\n?<td>(.+?)</td><td>.*?</td>|gs) {
		$place = $1;
		$temperature = $2;
		$scale = $3;
		$humidity = $4;
		$conditions = $5;
		$counter++;
		&_debug("MULTI-LOCATION PARSED $counter: conditions: $conditions :: temperature $temperature * $scale :: humidity $humidity\% :: place $place");
		if ($scale =~ /c/i) {
			&_debug("Temperature in Celsius. Converting accordingly");
			$celsius = $temperature;
			$fahrenheit = int(($temperature * 1.8) + 32);
			}
		elsif ($scale =~ /f/i) {
			&_debug("Temperature in Fahrenheit. Converting accordingly");
			$fahrenheit = $temperature;
			$celsius = int(($temperature  - 32)  / 1.8);
			}
		else {
			&_debug("WARNING: Temperature is neither in Celsius or Fahrenheit");
			$celsius = $temperature;
			$fahrenheit = $temperature;
			}
		push (@$arrayref, {
			place	=>	$place,
			celsius	=>	$celsius,
			fahrenheit	=>	$fahrenheit,
			humidity	=>	$humidity,
			conditions	=>	$conditions
			});
		}
	#
	# The second format is to match single-listing matches:
	#
	if ($document =~ /Observed at/) {
		$place = $self->{_place};
		($temperature,$scale) = ($document =~ m|<tr><td>Temperature</td>\n<td>\n(\d+)&#176;(\w)|);
		($humidity) = ($document =~ m|<tr><td>Humidity</td>\n<td>(\d+)\%</td></tr>\n|);
		($conditions) = ($document =~ m|<tr><td>Conditions</td>\n<td>(.+?)</td></tr>\n|);
		$counter++;
		&_debug("SINGLE-LOCATION PARSED $counter: $place: $conditions: $temperature * $scale . $humidity\% humity");
                if ($scale =~ /c/i) {
                        &_debug("Temperature in Celsius. Converting accordingly");
                        $celsius = $temperature;
                        $fahrenheit = int(($temperature * 1.8) + 32);
                        }
                elsif ($scale =~ /f/i) {
                        &_debug("Temperature in Fahrenheit. Converting accordingly");
                        $fahrenheit = $temperature;
                        $celsius = int(($temperature  - 32)  / 1.8);
                        }
                else {
                        &_debug("WARNING: Temperature is neither in Celsius or Fahrenheit");
                        $celsius = $temperature;
                        $fahrenheit = $temperature;
                        }
                push (@$arrayref, {
                        place   =>      $place,
                        celsius =>      $celsius,
                        fahrenheit      =>      $fahrenheit,
                        humidity        =>      $humidity,
                        conditions      =>      $conditions
                        });
		}
	if (!$counter) {
		&_debug("No matching places found");
		return undef;
		}
	else {
		return $arrayref;
		}
	}



1;
