# This is free and unencumbered software released into the public domain.

# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.

# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

#  For more information, please refer to <http://unlicense.org/>

# See also https://www.RainTMC.nl/overRainTMC/gratis-weerdata

# V 1.0 release über Github

package main;

use JSON;
use strict;
use warnings;
use HttpUtils;

#####################################
sub RainTMC_Initialize($) {

    my ($hash) = @_;

    $hash->{DefFn}       = "RainTMC_Define";
    $hash->{UndefFn}     = "RainTMC_Undef";
    $hash->{GetFn}       = "RainTMC_Get";
    $hash->{AttrList}    = $readingFnAttributes;
}

###################################
sub RainTMC_Get($$@) {

    my ( $hash, $name, $opt, @args ) = @_;

    return "\"get $name\" needs at least one argument" unless ( defined($opt) );

    if ( $opt eq "refresh" ) {
        RainTMC_RequestUpdate($hash);
        return "";
    }  elsif ( $opt eq "rainDuration" ) {
        my $begin = $hash->{".rainBeginTS"} ;
        my $end = $hash->{".rainEndTS"} ;
        Log3($name,3,"End: $end Neginf: $begin");
        if ( $begin != $end ) {
            return int(($end - $begin)/60);
        }
    }  elsif ( $opt eq "startsIn" ) {
        my $begin = $hash->{".rainBeginTS"}  ;
        if ($begin > time()) {
            return int (($begin - time() )/60);
        } elsif (ReadingsVal( $name, "rainNow", 0 )> 0 ) {
            return "raining";
        } else {
            return "unknown";
        }
    } else {
        return "Unknown argument $opt, choose one of refresh:noArg startsIn:noArg rainDuration:noArg";
    }
}

#####################################
sub RainTMC_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer($hash);
    return undef;
}


#####################################
sub RainTMC_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t][ \t]*", $def );
    my $latitude;
    my $longitude;

    if ( ( int(@a) == 2 ) && ( AttrVal( "global", "latitude", -255 ) != -255 ) )
    {
        $latitude  = AttrVal( "global", "latitude",  51 );
        $longitude = AttrVal( "global", "longitude", 7 );
    }
    elsif ( int(@a) == 4 ) {
        $latitude  = $a[2];
        $longitude = $a[3];
    }
    else {
        return
          int(@a)
          . " <=syntax: define <name> RainTMC [<latitude> <longitude>]";
    }

    $hash->{STATE} = "Initialized";

    my $name = $a[0];

    # alle fünf Minuten
    my $interval = 60 * 4;

    $hash->{INTERVAL}  = $interval;
    $hash->{LATITUDE}  = $latitude;
    $hash->{LONGITUDE} = $longitude;
    $hash->{URL} ="https://api.themeteocompany.com/precipitation/getforecastbylatlon/?radius=0&lat="
      . $hash->{LATITUDE} . "&lon="
      . $hash->{LONGITUDE};
    
    $hash->{READINGS}{rainBegin}{TIME} = TimeNow();
    $hash->{READINGS}{rainBegin}{VAL}  = "unknown";
    
    $hash->{".rainData"}  = "unknown";

    $hash->{READINGS}{rainDataStart}{TIME} = TimeNow();
    $hash->{READINGS}{rainDataStart}{VAL}  = "unknown";

    $hash->{READINGS}{rainNow}{TIME}    = TimeNow();
    $hash->{READINGS}{rainNow}{VAL}     = "unknown";
    
    $hash->{READINGS}{rainEnd}{TIME}    = TimeNow();
    $hash->{READINGS}{rainEnd}{VAL}     = "unknown";
    
    $hash->{READINGS}{rainAmount}{TIME} = TimeNow();
    $hash->{READINGS}{rainAmount}{VAL}  = "init";

    RainTMC_RequestUpdate($hash);
    RainTMC_ScheduleUpdate($hash);
    # InternalTimer( gettimeofday() + $hash->{INTERVAL},  "RainTMC_ScheduleUpdate", $hash, 0 );

    return undef;
}

sub RainTMC_ScheduleUpdate($) {
    my ($hash) = @_;
    my $nextupdate = 0;
    RemoveInternalTimer( $hash, "RainTMC_ScheduleUpdate" );

    if ( !$hash->{SHORTRELOAD} ) {
        $nextupdate = gettimeofday() + $hash->{INTERVAL};
    }
    else {
        $nextupdate = gettimeofday() + 90;
        delete $hash->{SHORTRELOAD};
    }
    InternalTimer( $nextupdate, "RainTMC_ScheduleUpdate", $hash );
    $hash->{NEXTUPDATE} = FmtDateTime($nextupdate);
    RainTMC_RequestUpdate($hash);

    return 1;
}

sub RainTMC_RequestUpdate($) {
    my ($hash) = @_;

    my $param = {
        url      => $hash->{URL},
        timeout  => 10,
        hash     => $hash,
        method   => "GET",
        callback => \&RainTMC_ParseHttpResponse
    };

    HttpUtils_NonblockingGet($param);
    Log3( $hash->{NAME}, 4, $hash->{NAME} . ": Update requested" );
}

sub RainTMC_ParseHttpResponse($) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err ne "" ) {
        Log3( $name, 3,
            "$name: error while requesting " . $param->{url} . " - $err" );
        $hash->{STATE}       = "Error: " . $err . " => " . $data;
        $hash->{SHORTRELOAD} = 1;
        RainTMC_ScheduleUpdate($hash);
    }
    elsif ( $data ne "" ) {

        my $rainbegin     = "unknown";
        my $rainend       = "unknown";
        my $rainbegints     = 0;
        my $rainendts       = 0;
        my $rainDataStart = "unknown";
        my $rainDataEnd = "unknown";
        my $rainData      = decode_json($data);
        my $rainMax       = 0;
        my $rainamount    = 0;
        my $rainLaMetric  = "";
        my $rain          = 0;
        my $rainNow       = 0;
        my $rainTotal     = 0;
        my $line          = 0;
        my $beginchanged  = 0;
        my $endchanged    = 0;
        my $endline       = 0;
        my $parse         = 1;
        my $l=0;
        my $as_png ="";
        my $as_htmlhead ='<tr style="font-size:x-small;"}>';
        my $as_html ="";

        my @array = @{$rainData->{ForecastResult}};
        my $logProxy = "";
        foreach my $a (@array) {
            
            $rain = $a->{Value};

            my $timestamp = $a->{TimeStamp};
            $timestamp =~ /\(([0-9]*)\)/ ;
            $timestamp = $1/1000;
            
            if ($timestamp > time()){

                if (($l % 4) == 0 ) {
                   $as_htmlhead .="<td >".substr(FmtDateTime($timestamp),-8,5)."</td>"
                } else {
                     $as_htmlhead .= "<td>&nbsp;</td>"
                }
                if (($a->{ColorAsRGB} eq "Transparent")||($rain==0)) {
                $as_html .= '<td bgcolor="#ffffff">&nbsp;</td>';
                } else{
                    $as_html .= '<td bgcolor="'. $a->{ColorAsRGB} .'">&nbsp;</td>';
                }
            $l +=1;
            if ($l == 1){
                $rainNow = $rain;
                $rainDataStart =FmtDateTime($timestamp);
                $rainData = $rain;
            }
            if ($l < 13)
            {
                $rainLaMetric .= int ($rain * 1000) . "," ;
            }
            $rainTotal += $rain/12;
            if ($parse) {
                $rainamount += $rain/12; 
                if ($beginchanged) {
                    if ( $rain > 0 ) {
                        $rainend = FmtDateTime($timestamp);
                        $rainendts = $timestamp;
                    }
                    else {
                        $rainend    = FmtDateTime($timestamp);
                        $rainendts = $timestamp;
                        $endchanged = 1;
                        $parse      = 0;      # Nur den ersten Schauer auswerten
                    }
                }
                else {
                    if ( $rain > 0 ) {
                        $rainbegin    = FmtDateTime($timestamp);
                        $rainbegints = $timestamp;
                        $rainendts = $timestamp;
                        $beginchanged = 1;
                        $rainend      = FmtDateTime($timestamp);
                    }
                }
               
            }
            my $logtime = FmtDateTime($timestamp);
            $logtime =~ tr/ /_/;
            $logProxy .= $logtime . " " . $rain."\r\n";
            $rainData .= ":" . $rain ;
            $rainMax = ( $rain > $rainMax ) ? $rain : $rainMax;
            $rainDataEnd =FmtDateTime($timestamp);
            $as_png .= "['". ( ( $l % 2 ) ? substr(FmtDateTime($timestamp),-8,5)  : "" ) . "'," . $rain ."],";
            }
        } # End foreach
        
        $rainLaMetric = substr( $rainLaMetric, 0, -1 );
        $as_png = substr( $as_png, 0, -1 );
        $as_html ="Niederschlagsvorhersage (<a href=./fhem?detail=$name>$name</a>)<BR><table>" . $as_htmlhead."</TR><tr style='border:2pt solid black'>". $as_html. "</tr></table>";
        $hash->{STATE} = sprintf( "%.2f", $rainNow );

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "rainNow", $rainNow );
        readingsBulkUpdateIfChanged( $hash, "rainLaMetric", $rainLaMetric );
        readingsBulkUpdateIfChanged( $hash, "rainAmount",sprintf( "%.3f", $rainamount * 12 ) );
        readingsBulkUpdateIfChanged( $hash, "rainTotal",sprintf( "%.3f", $rainTotal * 12 ) );
        readingsBulkUpdateIfChanged( $hash, "rainDataStart", $rainDataStart );
        readingsBulkUpdateIfChanged( $hash, "rainDataEnd", $rainDataEnd );
        $hash->{".rainData"} = $rainData ;
        $hash->{".PNG"} = $as_png;
        $hash->{".HTML"} = $as_html;
        $hash->{".logProxy"} = $logProxy;
        
        $hash->{".rainBeginTS"} = $rainbegints;
        $hash->{".rainEndTS"} = $rainendts;
             
        readingsBulkUpdateIfChanged( $hash, "rainMax", sprintf( "%.3f", $rainMax ) );
        readingsBulkUpdateIfChanged( $hash, "rainBegin", $rainbegin, $beginchanged );
        readingsBulkUpdateIfChanged( $hash, "rainEnd", $rainend, $endchanged );
        readingsEndUpdate( $hash, 1 );
    }
}

sub RainTMC_logProxy($) {
    my ($name) = @_;
    my $hash   = $defs{$name};
    my $ret;

    return ( $hash->{".logProxy"}, 0, ReadingsVal( $name, "rainMax", 0 ) );
}


sub RainTMC_HTML($) {
    my ($name) = @_;
    my $hash   = $defs{$name};
    
    return  $hash->{".HTML"};
}


sub RainTMC_PNG($) {
    my ($name) = @_;
    my $retval = '<div id="chart_div_'.$name.'"; ';
$retval .= <<'END_MESSAGE';
 style="width:100%; height:100%"></div>
<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
 <script type="text/javascript">

     google.charts.load("current", {packages:["corechart"]});
      google.charts.setOnLoadCallback(drawChart);
      function drawChart() {
        var data = google.visualization.arrayToDataTable([
          ['string', 'Regen'],
END_MESSAGE

    $retval .= $defs{$name}->{".PNG"};
    $retval .= <<'END_MESSAGE';
]);

 var options = {
          title: 'Niederschlag',
END_MESSAGE
    $retval .= "subtitle: 'Vorhersage (" . $name . ")',";

    $retval .= <<'END_MESSAGE';
          hAxis: {slantedText:true, slantedTextAngle:45,
              textStyle: {
              fontSize: 10}
              },
          vAxis: {minValue: 0}
        };

        var my_div = document.getElementById(
END_MESSAGE

    $retval .='"chart_div_'.$name.'");';

$retval .= <<'END_MESSAGE';
        var chart = new google.visualization.AreaChart(my_div);
        google.visualization.events.addListener(chart, 'ready', function () {
        my_div.innerHTML = '<img src="' + chart.getImageURI() + '">';
    });

        chart.draw(data, options);}
    </script>
END_MESSAGE
    return $retval;
}

1;

=pod

=item summary Rain prediction

=item summary_DE Regenvorhersage auf Basis des Wetterdienstes https://www.themeteocompany.com

=begin html
Only german documentation available
=end html

=begin html_DE

<a name="RainTMC"></a>
<h2>RainTMC</h2>
<ul>
<p>Niederschlagsvorhersage auf Basis von Wetterdaten von <a href="https://www.themeteocompany.com/">The Meteo Company</a></p>
<h3>Define</h3>
<p><code>define &lt;name&gt; RainTMC &lt;Logitude&gt; &lt;Latitude&gt;</code></p>
<p>Die Geokoordinaten können weg gelassen werden falls es eine entsprechende Definition im <code>global</code> Device gibt.</p>
<h3>Get</h3>
<ul>
<li><code>rainDuration</code> Die voraussichtliche Dauer des nächsten Schauers in Minuten</li>
<li><code>startsIn</code> Der Regen beginnt in x Minuten</li>
<li><code>refresh</code> Neue Daten werde nonblocking abgefragt</li>
</ul>
<h3>Readings</h3>
<ul>
<li><code>rainMax</code> Die maximale Regenmenge für ein 5 Min. Intervall auf Basis der vorliegenden Daten.</li>
<li><code>rainDataStart</code> Begin der aktuellen Regenvorhersage. Triggert das Update der Graphen</li>
<li><code>rainNow</code> Die vorhergesagte Regenmenge für das aktuelle 5 Min. Intervall in mm/m² pro Stunden</li>
<li><code>rainAmount</code> Die Regenmenge die im kommenden Regenschauer herunterkommen soll</li>
<li><code>rainDataEnd</code> Ende der Regenvorhersage</li>
<li><code>rainTotal</code> Die Regenmenge die in dem Vorhersage enthalten ist</li>
<li><code>rainLametric</code> Die näcshten 12 Regenmengen aufbereitet für ein LaMetric Display</li>
<li><code>rainBegin</code> Die Uhrzeit des kommenden Regenbegins oder "unknown"</li>
<li><code>rainEnd</code> Die Uhrzeit des kommenden Regenendes oder "unknown"</li>
</ul>
<h3>Visualisierung</h3>
<p>Zur Visualisierung gibt es drei Funktionen:</p>
<p>Die Funktionen <code>RainTMC_HTML</code> und <code>RainTMC_PNG</code> können im FHEMWEB verwendet werden. Die Funktion <code>RainTMC_logProxy</code> kann in Verbindung mit SVG oder im FTUI vorzugsweise mit dem Highchart Widget eingesetzt werden.</P>
<ul>
<li><code>{RainTMC_HTML(&lt;DEVICE&gt;)}</code> also z.B. {RainTMC_HTML("R")} gibt einen HTML Balken mit einer farblichen Representation der Regenmenge aus.</li>
<li><code>{RainTMC_PNG(&lt;DEVICE&gt;)}</code> also z.B. {RainTMC_PNG("R")} gibt eine mit der google Charts API generierte Grafik zurück</li>
<li><code>{RainTMC_logProxy(&lt;DEVICE&gt;)}</code> also z.B. {RainTMC_logProxy("R")} kann in Verbindung mit einem Logproxy Device die typischen FHEM und FTUI Charts erstellen.</li>
</ul>
</ul>

=end html_DE
=cut
