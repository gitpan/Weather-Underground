package Weather::Underground;

#
# $Header: /cvsroot/weather::underground/Weather/Underground/Underground.pm,v 1.21 2003/10/31 05:14:44 mina Exp $
#

use strict;
use vars qw($VERSION $CGI $CGIVAR $MYNAME $DEBUG);
use LWP::Simple qw($ua get);
use HTML::TokeParser;

$VERSION = '2.11';

#
# GLOBAL Variables Assignments
#

$CGI    = 'http://www.wunderground.com/cgi-bin/findweather/getForecast';
$CGIVAR = 'query';
$MYNAME = "Weather::Underground";
$DEBUG  = 0;

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

	temperature_celsius
	(the temperature in celsius)

	temperature_fahrenheit
	(the temperature in fahrenheit)

	humidity
	(humidity percentage)

	conditions
	(current sky, example: 'Partly cloudy')

	wind
	(wind direction and speed)

	pressure
	(the barometric pressure)

	windchill_celsius
	(the temperature in celsius with wind chill considered)

	windchill_fahrenheit
	(the temperature in fahrenheit with wind chill considered)

	updated
	(when the content was last updated on the server)

=head1 NOTICE

1. Your query may result in more than 1 match. Each match is a hash reference added as a new value in the array which getweather() returns the reference to.

2. Due to the differences between single and multiple-location matches, some of the keys listed above may not be available in multi-location matches.

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

	print "The celsius temperature at the first matching place is " . $arrayref->[0]->{temperature_celsius} . "\n";

=head1 ERRORS

All methods return something that evaluates to true when successful, or undef when not successful.

If the constructor or a method returns undef, the variable $@ will contain a text string containing the error that occurred.

=head1 AUTHOR

Mina Naguib
http://www.topfx.com
mnaguib@cpan.org

=head1 COPYRIGHT

Copyright (C) 2002-2003 Mina Naguib.  All rights reserved.  Use is subject to the Perl license.

=cut

#
# Public methods
#

sub new {
	my ($class, %parameters) = @_;
	my $self;
	$DEBUG = $parameters{debug};
	_debug("Creating a new $MYNAME object");
	if (!$parameters{place}) {
		_debug("ERROR: Location not specified");
		return undef;
	}
	$self = {
		_place => $parameters{place},
		_url   => $CGI . '?' . $CGIVAR . '=' . $parameters{place}
	};
	bless($self, $class);
	return $self;
}

sub getweather {
	my ($self) = @_;
	my $document;
	my $parser;
	my $token;
	my %state;
	my $text;
	my $arrayref = [];
	my $oldagent;

	_debug("Getting weather info for " . $self->{_place});
	_debug("Retrieving url " . $self->{_url});

	$oldagent = $ua->agent();
	$ua->agent("Weather::Underground version $VERSION");
	$document = get($self->{_url});
	$ua->agent($oldagent);

	if (!$document) {
		_debug("Could not retrieve HTML document " . $self->{_url});
		return undef;
	}
	else {
		_debug("I retrieved the following data:\n\n\n\n\n$document\n\n\n\n\n");
	}

	#
	# Some minor cleanup to preserve our sanity and regexes:
	#
	$document =~ s/<\/?[bi]>//gi;
	$document =~ s/<br>/\n/gi;
	_debug("After cleanup, document data:\n\n\n\n\n$document\n\n\n\n\n");

	_debug("Beginning parsing");
	unless ($parser = HTML::TokeParser->new(\$document)) {
		_debug("Failed to create parser object");
		return undef;
	}

	if ($document =~ /search results/i) {

		#
		# We use multi-location algorithm
		#
		_debug("Multi-location result detected");

		while ($token = $parser->get_token) {
			if ($token->[0] eq "T" && !$token->[2] && $state{"intable"}) {

				#
				# The beginning of a text token - retrieve the whole thing and clean it up
				#
				$text = $token->[1] . $parser->get_text();
				$text =~ s/&#([0-9]{1,3});/chr($1)/ge;
				$text =~ s/&nbsp;/ /gi;
				next if $text !~ /[a-z0-9]/i;
				$text =~ s/^\s+//g;
				$text =~ s/\s+$//g;
				$text =~ s/\s+/ /g;
				if ($state{"inheader"}) {

					#
					# This is the title for a header column - store it for later use when encountering content under same column
					#
					$state{"header_$state{headernumber}"} = uc($text);
				}
				elsif ($state{"incontent"}) {

					#
					# This is content we're interested in - store it under the header title of the same column number
					#
					$state{ "content_" . $state{ "header_" . $state{"contentnumber"} } } = $text;
				}
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TH") {

				#
				# A new cell in the header of the table that has the info we need has started
				#
				$state{"headernumber"}++;
				$state{"inheader"}  = 1;
				$state{"intable"}   = 1;
				$state{"incontent"} = 0;
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TR" && $state{"intable"}) {

				#
				# A new row in the table we're interested in started
				#
				if ($state{"inheader"}) {

					#
					# This is the end of the header and the beginning of the content rows
					#
					$state{"inheader"}      = 0;
					$state{"incontent"}     = 1;
					$state{"contentnumber"} = 0;
				}
				elsif ($state{"incontent"}) {

					#
					# This is a new content row beginning
					#
					$state{"contentnumber"} = 0;

					#
					# Erase the data remembered from any previous rows
					#
					foreach (keys %state) {
						delete $state{$_} if /^content_/;
					}
				}
			}
			elsif ($token->[0] eq "E" && uc($token->[1]) eq "TR" && $state{"incontent"}) {

				#
				# This is the end of a content row
				#
				# Save the data
				#
				_state2result(\%state, $arrayref);

			}

			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TD" && $state{"incontent"}) {

				#
				# The beginning of a new cell with content
				#
				$state{"contentnumber"}++;
			}
			elsif ($token->[0] eq "E" && uc($token->[1]) eq "TABLE" && $state{"intable"}) {

				#
				# The table that has the data is finished - no need to keep parsing
				#
				last;
			}
		}

	}

	else {

		#
		# We use single-location algorithm
		#
		while ($token = $parser->get_token) {
			if ($token->[0] eq "T" && !$token->[2]) {

				#
				# The beginning of a text token - retrieve the whole thing and clean it up
				#
				$text = $token->[1] . $parser->get_text();
				$text =~ s/&#([0-9]{1,3});/chr($1)/ge;
				$text =~ s/&nbsp;/ /gi;
				next if $text !~ /[a-z0-9]/i;
				$text =~ s/^\s+//g;
				$text =~ s/\s+$//g;
				$text =~ s/\s+/ /g;

				if (uc($text) eq "CONDITIONS" && !$state{"intable"}) {

					#
					# We just entered the table that has the data we want
					#
					$state{"intable"}     = 1;
					$state{"intopheader"} = 0;
					$state{"incontent"}   = 0;
				}
				elsif ($state{"intopheader"}) {

					#
					# This is the top header
					#
					($state{"content_UPDATED"}) = ($text =~ /updated\s*:?\s*(.+?)\s*observ|\Z/i);
					($state{"content_PLACE"})   = ($text =~ /observed\s+at\s+:?\s*(.+)/i);
				}
				elsif ($state{"incontent"}) {

					#
					# This is either a header or a content, depending on the column number
					#
					if ($state{"contentnumber"} == 1) {

						#
						# It's a header - remember to associate the upcoming content under it
						#
						$state{"header"} = uc($text);
					}
					else {

						#
						# It's a content - associate it with the previous header
						#
						$state{ "content_" . $state{"header"} } = $text;
					}
				}
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TR" && $state{"intable"}) {

				#
				# It's a new row in the table we're interested in
				#
				if (!$state{"intopheader"} && !$state{"incontent"}) {

					#
					# Should never reach here - but in case we do, we're about to start the top header
					#
					$state{"intopheader"} = 1;
				}
				elsif ($state{"intopheader"}) {

					#
					# The top header is finished and the content is coming up
					#
					$state{"intopheader"} = 0;
					$state{"incontent"}   = 1;
				}
				elsif ($state{"incontent"}) {

					#
					# A new header+content coming up
					#
					$state{"contentnumber"} = 0;
				}
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TD" && $state{"incontent"}) {

				#
				# A new header or content cell is starting
				#
				$state{"contentnumber"}++;
			}
			elsif ($token->[0] eq "E" && uc($token->[1]) eq "TABLE" && $state{"intable"}) {

				#
				# Done parsing - save the data
				#
				_state2result(\%state, $arrayref);

				#
				# No need to keep going - it's only 1 location
				#
				last;
			}
		}
	}

	if (!@$arrayref) {
		_debug("No matching places found");
		return undef;
	}
	else {
		return $arrayref;
	}

}

##################################################################################################################################
#
# Internal subroutines
#
sub _debug {
	my $notice = shift;
	$@ = $notice;
	if ($DEBUG) {
		print "$MYNAME DEBUG NOTE: $notice\n";
		return 1;
	}
	return 0;
}

sub _state2result {
	my $stateref = shift;
	my $arrayref = shift;
	my ($temperature_fahrenheit, $temperature_celsius);
	my ($windchill_fahrenheit,   $windchill_celsius);

	$stateref->{"content_TEMPERATURE"} =~ s/\s//g;
	($temperature_celsius)    = ($stateref->{"content_TEMPERATURE"} =~ /(-?\d+)[^a-z0-9]*?c/i);
	($temperature_fahrenheit) = ($stateref->{"content_TEMPERATURE"} =~ /(-?\d+)[^a-z0-9]*?f/i);
	if (!length($temperature_celsius) && length($temperature_fahrenheit)) {
		$temperature_celsius = ($temperature_fahrenheit - 32) / 1.8;
	}
	elsif (!length($temperature_fahrenheit) && length($temperature_celsius)) {
		$temperature_fahrenheit = ($temperature_celsius * 1.8) + 32;
	}

	$stateref->{"content_WINDCHILL"} =~ s/\s//g;
	($windchill_celsius)    = ($stateref->{"content_WINDCHILL"} =~ /(-?\d+)[^a-z0-9]*?c/i);
	($windchill_fahrenheit) = ($stateref->{"content_WINDCHILL"} =~ /(-?\d+)[^a-z0-9]*?f/i);
	if (!length($windchill_celsius) && length($windchill_fahrenheit)) {
		$windchill_celsius = ($windchill_fahrenheit - 32) / 1.8;
	}
	elsif (!length($windchill_fahrenheit) && length($windchill_celsius)) {
		$windchill_fahrenheit = ($windchill_celsius * 1.8) + 32;
	}

	$stateref->{"content_HUMIDITY"} =~ s/[^0-9]//g;
	push(
		@$arrayref,
		{
			place                  => $stateref->{"content_PLACE"},
			temperature_celsius    => $temperature_celsius,
			temperature_fahrenheit => $temperature_fahrenheit,
			celsius                => $temperature_celsius,                # Legacy
			fahrenheit             => $temperature_fahrenheit,             # Legacy
			windchill_celsius      => $windchill_celsius,
			windchill_fahrenheit   => $windchill_fahrenheit,
			humidity               => $stateref->{"content_HUMIDITY"},
			conditions             => $stateref->{"content_CONDITIONS"},
			wind                   => $stateref->{"content_WIND"},
			updated                => $stateref->{"content_UPDATED"},
			pressure               => $stateref->{"content_PRESSURE"},
		}
	);

}

# Leave me alone:
1;
