package Weather::Underground;

#
# $Header: /cvsroot/weather::underground/Weather/Underground/Underground.pm,v 1.33 2004/06/08 17:20:16 mina Exp $
#

use strict;
use vars qw($VERSION $CGI $CGIVAR $MYNAME $DEBUG %MODULES);
use LWP::Simple qw($ua get);
use HTML::TokeParser;
use Fcntl qw(:flock);

$VERSION = '2.19';

#
# GLOBAL Variables Assignments
#

$CGI    = 'http://www.wunderground.com/cgi-bin/findweather/getForecast';
$CGIVAR = 'query';
$MYNAME = "Weather::Underground";
$DEBUG  = 0;

%MODULES = (
	"Data::Dumper" => 0,
	"Storable"     => 0,
	"FreezeThaw"   => 0,
);

foreach (keys %MODULES) {
	eval { eval("require $_;") || die "$_ not found"; };
	$MODULES{$_} = $@ ? 0 : 1;
}

=head1 NAME

Weather::Underground - Perl extension for retrieving weather information from wunderground.com

=head1 SYNOPSIS

	use Weather::Underground;

	$weather = Weather::Underground->new(
		place => "Montreal, Canada",
		debug => 0,
		)
		|| die "Error, could not create new weather object: $@\n";

	$arrayref = $weather->get_weather()
		|| die "Error, calling get_weather() failed: $@\n";

	foreach (@$arrayref) {
		print "MATCH:\n";
		while (($key, $value) = each %{$_}) {
			print "\t$key = $value\n";
		}
	}

=head1 DESCRIPTION

Weather::Underground is a perl module which provides a simple OO interface to retrieving weather data for a geographic location.  It does so by querying wunderground.com and parsing the returned results.

=head1 CONSTRUCTOR

=over 4

=item new(hash or hashref);

Creates and returns a new Weather::Underground object.

Takes either a hash (as the SYNOPSIS shows) or a hashref

Required keys in the hash:

=over 4

=item place

This key should be assigned the value of the geographical place you would like to retrieve the weather information for.  The format of specifying the place really depends on wunderground.com more than it depends on this perl module, however at the time of this writing they accept 'City', 'City, State', 'State', 'State, Country' and 'Country'.

=back

Optional keys in the hash:

=over 4

=item cache_file

This key should be assigned a file name to use as a cache.  The module will store and use data from that file instead of querying wunderground.com if cache_max_age has not been exceeded.

This key is ignored if the cache_max_age key is not supplied.

=item cache_max_age

This key should be assigned a numeric value which is the number of seconds after which any data in the cache_file will be considered too old and a new request will be made to wunderground.com

This key is ignored if the cache_file key is not supplied.

=item debug

This key should be set to a true or false false. A false value means no debugging information will be printed, a true value means debug information will be printed.

=item timeout

If the default timeout for the LWP::UserAgent request (180 seconds at the time of this writing) is not enough for you, you can change the timeout by providing this key.  It should contain the timeout for the HTTP request seconds in seconds.

=back

=back

=head1 METHODS

=over 4

=item get_weather()

This method is used to initiate the connection to wunderground.com, query their system, and parse the results or retrieve the results from the cache_file constructor key if appropriate.

If no results are found, returns undef.

If results are found, returns an array reference.  Each element in the array is a hash reference. Each hash contains information about a place that matched the query;

Each hash contains the following keys:

=over 4

=item place

(the exact place that was matched)

=item temperature_celsius

(the temperature in celsius)

=item temperature_fahrenheit

(the temperature in fahrenheit)

=item humidity

(humidity percentage)

=item conditions

(current sky, example: 'Partly cloudy')

=item wind

(wind direction and speed)

=item pressure

(the barometric pressure)

=item windchill_celsius

(the temperature in celsius with wind chill considered)

=item windchill_fahrenheit

(the temperature in fahrenheit with wind chill considered)

=item updated

(when the content was last updated on the server)

=back

=back

=head1 NOTICE

=over 4

=item 1

Your query may result in more than 1 match. Each match is a hash reference added as a new value in the array which get_weather() returns the reference to.

=item 2

Due to the differences between single and multiple-location matches, some of the keys listed above may not be available in multi-location matches.

=back

=head1 EXAMPLES

=over 4

=item Example 1: Print all matching information

	See SYNOPSIS

=item Example 2: Print the Celsius temperature of the first matching place

	use Weather::Underground;

	$weather = Weather::Underground->new(
		place   =>      "Montreal",
		debug           =>      0
		)
		|| die "Error, could not create new weather object: $@\n";

	$arrayref = $weather->get_weather()
		|| die "Error, calling get_weather() failed: $@\n";

	print "The celsius temperature at $arrayref->[0]->{place} is $arrayref->[0]->{temperature_celsius}\n";

=back

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
# Public methods:
#

sub new {
	my $class = shift;
	my $self;
	my %parameters;
	my $module;
	my $raw;
	my $cache;
	local (*FH);

	if (ref($_[0]) eq "HASH") {
		%parameters = %{ $_[0] };
	}
	else {
		%parameters = @_;
	}

	$DEBUG = $parameters{debug};
	_debug("Creating a new $MYNAME object");
	if (!$parameters{place}) {
		_debug("ERROR: Location not specified");
		return undef;
	}
	$self = {
		"place"   => $parameters{place},
		"timeout" => $parameters{timeout},
		"_url"    => $CGI . '?' . $CGIVAR . '=' . $parameters{place}
	};
	if ($parameters{cache_max_age} && $parameters{cache_file}) {

		#
		# We've been requested to use caching - let's do sanity, then populate $module and $cache
		#
		if (!grep { $_ } values %MODULES) {
			_debug("Error: Can not use cache_file when none of the needed serialization modules (" . join(" or ", keys %MODULES) . ") are installed");
			return undef;
		}
		if ($parameters{cache_max_age} !~ /^[0-9.]+$/) {
			_debug("Error: Supplied cache_max_age key must be a number");
			return undef;
		}
		if (-f $parameters{cache_file}) {

			#
			# The cache file already exists
			#
			if (!open(FH, $parameters{cache_file})) {
				_debug("Error: Failed to open $parameters{cache_file} for reading: $!");
				return undef;
			}
			if (!flock(FH, LOCK_EX)) {
				close(FH);
				_debug("Error: Failed to obtain an exclusive lock on $parameters{cache_file}: $!");
				return undef;
			}
			if (!seek(FH, 0, 0)) {
				flock(FH, LOCK_UN);
				close(FH);
				_debug("Error: Failed to seek to the beginning of $parameters{cache_file}: $!");
				return undef;
			}
			$module = <FH>;
			chomp $module;
			if (!exists $MODULES{$module}) {
				flock(FH, LOCK_UN);
				close(FH);
				_debug("cache_file $parameters{cache_file} does not appear to be a valid Weather::Underground cache file");
				return undef;
			}
			elsif (!$MODULES{$module}) {
				flock(FH, LOCK_UN);
				close(FH);
				_debug("cache_file $parameters{cache_file} with serialization module $module which is not installed on this machine.  Please install it or delete the cache file to start with a fresh one");
				return undef;
			}

			$cache = "";
			$raw   = "";
			while (<FH>) {
				$raw .= $_;
			}
			flock(FH, LOCK_UN);
			close(FH);

			#
			# Now deserialize $cache
			#
			if ($module eq "Data::Dumper") {
				my $VAR1;
				$cache = eval($raw);
			}
			elsif ($module eq "Storable") {
				$cache = Storable::thaw($raw);
			}
			elsif ($module eq "FreezeThaw") {
				$cache = FreezeThaw::thaw($raw);
			}

			if (ref($cache) ne "HASH") {
				_debug("Failed to deserialize cache with module $module - [$!] [$@] got non-hashref [$cache] from raw [$raw]");
				return undef;
			}
		}
		else {

			#
			# The cache file does not exist - create new one
			#
			if (!open(FH, ">$parameters{cache_file}")) {
				_debug("Error: Failed to open $parameters{cache_file} for writing: $!");
				return undef;
			}
			close(FH);
			$module = (sort grep { $MODULES{$_} } keys %MODULES)[0];
			$cache = {};
		}

		#
		# If we've reached here, cache_file and cache_max_age are good
		#
		$self->{cache_file}    = $parameters{cache_file};
		$self->{cache_max_age} = $parameters{cache_max_age};
		$self->{_cache_module} = $module;
		$self->{_cache_cache}  = $cache;
	}
	elsif ($parameters{cache_max_age} || $parameters{cache_file}) {
		_debug("cache_max_age or cache_file was supplied without the other - ignoring it");
	}

	bless($self, $class);
	return $self;
}

# legacy:
sub getweather {
	return get_weather(@_);
}

sub get_weather {
	my ($self) = @_;
	my $document;
	my $parser;
	my $token;
	my %state;
	my $text;
	my $arrayref = [];
	my $oldagent;
	local (*FH);

	_debug("Getting weather info for " . $self->{place});

	if ($self->{_cache_cache}) {

		#
		# We have a cache
		#
		_debug("Checking cache");
		if (exists $self->{_cache_cache}->{ $self->{place} }) {
			if ((time - $self->{_cache_cache}->{ $self->{place} }->{"time"}) <= $self->{cache_max_age}) {
				_debug("Found in cache within cache_max_age");
				return $self->{_cache_cache}->{ $self->{place} }->{"arrayref"};
			}
			else {
				_debug("Found in cache but too old");
			}
		}
	}

	_debug("Retrieving url " . $self->{_url});

	if ($self->{timeout}) {
		_debug("Setting timeout for LWP::Simple's LWP::UserAgent object to $self->{timeout}");
		$ua->timeout($self->{timeout});
	}
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
					_debug("Header text read [$text]");
					$state{"header_$state{headernumber}"} = uc($text);
				}
				elsif ($state{"incontent"}) {

					#
					# This is content we're interested in - store it under the header title of the same column number
					#
					_debug("Content text read [$text]");
					$state{ "content_" . $state{ "header_" . $state{"contentnumber"} } } = $text;
				}
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TH") {

				#
				# A new cell in the header of the table that has the info we need has started
				#
				_debug("A new table header cell started");
				_debug("This means we entered the interesting table") unless $state{"intable"};
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
					_debug("A new row started while we're in header - assuming end of header and upcoming content");
					$state{"inheader"}      = 0;
					$state{"incontent"}     = 1;
					$state{"contentnumber"} = 0;
				}
				elsif ($state{"incontent"}) {

					#
					# This is a new content row beginning
					#
					_debug("A new row containing content started");
					$state{"contentnumber"} = 0;

					#
					# Erase the data remembered from any previous rows
					#
					foreach (keys %state) {
						delete $state{$_} if /^content_/;
					}
				}
				else {

					#
					# Shouldn't reach here
					#
					_debug("Shouldn't see this - new row started while we're in table but we're not in header or content!");
				}
			}
			elsif ($token->[0] eq "E" && uc($token->[1]) eq "TR" && $state{"incontent"}) {

				#
				# This is the end of a content row
				#
				# Save the data
				#
				_debug("End of content row");
				_state2result(\%state, $arrayref);

			}

			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TD" && $state{"incontent"}) {

				#
				# The beginning of a new cell with content
				#
				_debug("Beginning of new content cell");
				$state{"contentnumber"}++;
			}
			elsif ($token->[0] eq "E" && uc($token->[1]) eq "TABLE" && $state{"intable"}) {

				#
				# The table that has the data is finished - no need to keep parsing
				#
				_debug("End of table while we're in table - we're done");
				last;
			}
		}

	}

	else {

		#
		# We use single-location algorithm
		#
		_debug("Single-location result detected");

		while ($token = $parser->get_token) {
			if ($token->[0] eq "T" && !$token->[2]) {

				#
				# The beginning of a text token - retrieve the whole thing and clean it up
				#
				$text = $token->[1] . $parser->get_text();
				$text =~ s/&#([0-9]{1,3});/chr($1)/ge;
				$text =~ s/&nbsp;/ /gi;
				$text =~ s/^\s*\W*\s*//g;
				$text =~ s/\s*\W*\s*$//g;
				$text =~ s/\s+/ /g;
				next if $text !~ /[a-z0-9]/i;
				next if $text eq "IMG";

				if ($state{"intable"} && !$state{"insummary"} && !$state{"incontent"}) {

					#
					# Text in the header
					#
					_debug("Matched text in header [$text]");
					if ($text =~ /updated\s*:?\s*(.+?)\s*observ/i) {
						_debug("Matched key UPDATED [$1]");
						$state{"content_UPDATED"} = $1;
					}
					if ($text =~ /observed\s+at\s+:?\s*(.+)/i) {
						_debug("Matched key PLACE [$1]");
						$state{"content_PLACE"} = $1;
					}
				}
				elsif ($state{"insummary"}) {

					#
					# Text in the summary
					#
					_debug("Matched text in summary [$text]");
					if ($text =~ /[0-9]/) {

						#
						# It's probably the temperature
						#
						_debug("Matched key TEMPERATURE");
						$state{"content_TEMPERATURE"} .= $text;
					}
					elsif ($text =~ /[a-z]/i) {

						#
						# It's probably the conditions
						#
						_debug("Matched key CONDITIONS");
						$state{"content_CONDITIONS"} = $text;
					}
				}
				elsif ($state{"incontent"}) {

					#
					# This is either a header or a content, depending on the column number
					#
					if ($state{"contentnumber"} == 1) {

						#
						# It's a header - remember to associate the upcoming content under it
						#
						_debug("Read header text [$text]");
						$state{"header"} = uc($text);
					}
					else {

						#
						# It's a content - associate it with the previous header
						#
						_debug("Read content text [$text]");
						$state{ "content_" . $state{"header"} } .= $text . " ";
					}
				}
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TR" && $state{"incontent"}) {

				#
				# A new header+content coming up
				#
				_debug("New content row starting");
				$state{"contentnumber"} = 0;
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TD" && $state{"incontent"}) {

				#
				# A new header or content cell is starting
				#
				_debug("New header or content cell starting");
				$state{"contentnumber"}++;
			}
			elsif ($token->[0] eq "S" && uc($token->[1]) eq "TABLE") {

				#
				# Start of some table
				#
				if (uc($token->[2]->{"id"}) eq "TABLE4") {

					#
					# Start of the left table
					#
					_debug("Entered left table");
					$state{"inlefttable"} = 1;
				}
				elsif (uc($token->[2]->{"class"}) eq "SMALLTABLE" && $state{"inlefttable"} && !$state{"intable"}) {

					#
					# The first table inside the left table is the main table we want
					#
					_debug("Entered main table");
					$state{"intable"}   = 1;
					$state{"insummary"} = 0;
					$state{"incontent"} = 0;
				}
				elsif ($state{"intable"}) {

					#
					# Start of a sub-table - just increment intable state so we detect closure of main table properly
					#
					_debug("Sub-table started");
					$state{"intable"}++;

					#
					# A new sub-table could mean we're entering summary or from summary to content
					#
					if (!$state{"insummary"} && !$state{"incontent"}) {
						_debug("That sub-table is the summary");
						$state{"insummary"} = 1;
					}
					elsif ($state{"insummary"}) {
						_debug("That sub-table is the content");
						$state{"insummary"} = 0;
						$state{"incontent"} = 1;
					}
				}
			}
			elsif ($token->[0] eq "E" && uc($token->[1]) eq "TABLE" && $state{"intable"}) {
				if (--$state{"intable"}) {

					#
					# Closed table was a sub-table - ignore it
					#
					_debug("Sub-table closed");
				}
				else {

					#
					# Main table closed - Done parsing - save the data
					#
					_debug("Main table closed - end of interesting data");
					_state2result(\%state, $arrayref);

					#
					# No need to keep going - it's only 1 location
					#
					last;
				}
			}
		}
	}

	if (!@$arrayref) {
		_debug("No matching places found");
		return undef;
	}
	else {
		if ($self->{cache_file}) {

			#
			# Let's save the result into the cache_file before we return it
			#
			_debug("Saving results into cache_file $self->{cache_file}");

			$self->{_cache_cache}->{ $self->{place} } = {
				"time"     => time,
				"arrayref" => $arrayref,
			};
			if (open(FH, ">$self->{cache_file}")) {
				if (flock(FH, LOCK_EX)) {
					if (seek(FH, 0, 0)) {
						print FH $self->{_cache_module};
						print FH "\n";
						if ($self->{_cache_module} eq "Data::Dumper") {
							print FH Data::Dumper::Dumper($self->{_cache_cache});
						}
						elsif ($self->{_cache_module} eq "Storable") {
							print FH Storable::freeze($self->{_cache_cache});
						}
						elsif ($self->{_cache_module} eq "FreezeThaw") {
							print FH FreezeThaw::freeze($self->{_cache_cache});
						}
						flock(FH, LOCK_UN);
						close(FH);
					}
					else {
						_debug("Error: Failed to seek to beginning of cache_file $self->{cache_file}: $!");
					}
				}
				else {
					_debug("Error: Failed to lock cache_file $self->{cache_file} exclusively: $!");
				}
			}
			else {
				_debug("Error: Failed to open cache_file $self->{cache_file} for writing: $!");
			}

		}
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

	#
	# Avoid some silly warnings of unitialized values
	#
	foreach (qw(content_PLACE content_TEMPERATURE content_WINDCHILL content_HUMIDITY content_CONDITIONS content_WIND content_UPDATED content_PRESSURE)) {
		exists($stateref->{$_}) or ($stateref->{$_} = "");
	}

	$stateref->{"content_TEMPERATURE"} =~ s/\s//g;
	($temperature_celsius)    = ($stateref->{"content_TEMPERATURE"} =~ /(-?(?:\d|\.)+)[^a-z0-9]*?c/i);
	($temperature_fahrenheit) = ($stateref->{"content_TEMPERATURE"} =~ /(-?(?:\d|\.)+)[^a-z0-9]*?f/i);
	if (!length($temperature_celsius) && length($temperature_fahrenheit)) {
		$temperature_celsius = ($temperature_fahrenheit - 32) / 1.8;
	}
	elsif (!length($temperature_fahrenheit) && length($temperature_celsius)) {
		$temperature_fahrenheit = ($temperature_celsius * 1.8) + 32;
	}

	$stateref->{"content_WINDCHILL"} =~ s/\s//g;
	($windchill_celsius)    = ($stateref->{"content_WINDCHILL"} =~ /(-?(?:\d|\.)+)[^a-z0-9]*?c/i);
	($windchill_fahrenheit) = ($stateref->{"content_WINDCHILL"} =~ /(-?(?:\d|\.)+)[^a-z0-9]*?f/i);
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
