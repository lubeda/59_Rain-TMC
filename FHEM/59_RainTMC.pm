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
    $hash->{AttrList}    = $readingFnAttributes;
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
    my $interval = 60 * 2;

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

       my $rainamount    = 0.0;
        my $rainbegin     = "unknown";
        my $rainend       = "unknown";
        my $rainDataStart = "unknown";
        my $rainData      = decode_json($data);
        my $rainMax       = 0;
        my $rain          = 0;
        my $rainNow       = 0;
        my $line          = 0;
        my $beginchanged  = 0;
        my $endchanged    = 0;
        my $endline       = 0;
        my $parse         = 1;
        my $l=0;
        my $as_png ="";

        my @array = @{$rainData->{ForecastResult}};
        my $logProxy = "";
        foreach my $a (@array) {

            $rain = $a->{Value};

            my $timestamp = $a->{TimeStamp};
            $timestamp =~ /\(([0-9]*)\)/ ;
            $timestamp = $1/1000;
            $l +=1;
            if ($l == 1){
                $rainNow = $rain;
                $rainDataStart =FmtDateTime($timestamp);
                $rainData = $rain;
            }
            if ($parse) {
                if ($beginchanged) {
                    if ( $rain > 0 ) {
                        $rainend = FmtDateTime($timestamp);
                    }
                    else {
                        $rainend    = FmtDateTime($timestamp);
                        $endchanged = 1;
                        $parse      = 0;      # Nur den ersten Schauer auswerten
                    }
                }
                else {
                    if ( $rain > 0 ) {
                        $rainbegin    = FmtDateTime($timestamp);
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
            
            $as_png .= "['". ( ( $l % 2 ) ? substr(FmtDateTime($timestamp),-8,5)  : "" ) . "'," . $rain ."],";
        }
        
        $as_png = substr( $as_png, 0, -1 );

        $hash->{STATE} = sprintf( "%.3f mm/h", $rainNow );

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "rainAmount",sprintf( "%.3f", $rainamount * 12 ) );
        readingsBulkUpdateIfChanged( $hash, "rainNow", $rainNow );
        readingsBulkUpdateIfChanged( $hash, "rainDataStart", $rainDataStart );
        $hash->{".rainData"} = $rainData ;
        $hash->{".PNG"} = $as_png;
        $hash->{"logProxy"} = $logProxy;
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

    return ( $hash->{"logProxy"}, 0, ReadingsVal( $name, "rainMax", 0 ) );
}

sub RainTMC_PNG($) {
    my ($name) = @_;
    my $retval;
    $retval = <<'END_MESSAGE';
<style>
.chart_div {width:400px; height:310px;}
</style>
END_MESSAGE

$retval .= '<div id="chart_div_$name"; ';
$retval .= <<'END_MESSAGE';
" style="width:100%; height:100%"></div>
<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
 <script type="text/javascript">

     google.charts.load("current", {packages:["corechart"]});
      google.charts.setOnLoadCallback(drawChart);
      function drawChart() {
        var data = google.visualization.arrayToDataTable([
          ['string', 'mm/m² per h'],
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

        var my_div = document.getElementById('chart_div');
        var chart = new google.visualization.AreaChart(document.getElementById('chart_div'));
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
=begin html_DE

<a name="RainTMC"></a>
<h3>RainTMC</h3>
<ul>
    <p>Niederschlagsvorhersage auf Basis von freien Wetterdaten <a href="">https://www.RainTMC.nl/overRainTMC/gratis-weerdata</a></p>
    <BR>
    <a name="RainTMCdefine"></a>
    <p><b>Define</b></p>
    <ul>
        <p><code>define &lt;name&gt; RainTMC &lt;Logitudename&gt; &lt;Latitude&gt;</code></p>
    </ul>
    <a name="RainTMCget"></a>
    <p><b>Get</b></p>
    <ul>
        <p>Folgende Werte kann man mit get abfragen:</p>
        <li>

            <p><code>rainDuration</code> Die voraussichtliche Dauer des n&auml;chsten Schauers in Minuten</p>
        </li>
        <li>
            <p><code>startsIn</code> Der Regen beginnt in x Minuten</p>
        </li>
        <li>
            <p><code>refresh</code> Neue Daten werde nonblocking abgefragt/</p>
        </li>
        <li>
            <p><code>testVal</code> Rechnet einen RainTMC Wert in mm/m² um ( zu Testzwecken)</p>
        </li>
    </ul>
    <a name="RainTMCreadings"></a>
    <p><b>Readings</b></p>
    <p>Folgende Readings bietet das Modul:</p><br>
    <ul><li>
            <code>rainNow</code> Die vorhergesagte Regenmenge f&uuml;r das aktuelle 5 Min. Intervall in mm/m² pro Stunden
    </li>
    <li><code>rainAmount</code> Die Regenmenge die im kommenden Regenschauer herunterkommen soll</li>
<li><code>rainBegin</code>Die Uhrzeit des kommenden
    Regenbegins oder "unknown"</li>    
    <li><code>rainEnd</code>Die Uhrzeit des kommenden Regenendes oder "unknown"</li>
</ul>
<a name="RainTMCfunctions"></a>
<p><b>Funktionen</b></p>

    <p>Zur Visualisierung gibt es drei Funktionen:</p> 
    <ul>
        <li><code>{RainTMC_HTML(<DEVICE>,<Pixel>)}</code> also z.B. {RainTMC_HTML("BR",500)} gibt eine reine HTML Liste zur&uuml;ck, der l&auml;ngste Balken hat dann 500 Pixel
            (nicht so schön ;-)) </li>
        <li><code>{RainTMC_PNG(<DEVICE>)}</code>also z.B. {RainTMC_PNG("BR")} gibt eine mit der google Charts API generierte Grafik zur&uuml;ck</li>
<li><code> {RainTMC_logProxy(
        <DEVICE>)}</code>also z.B. {RainTMC_logProxy("BR")} kann in Verbindung mit einem Logproxy Device die typischen FHEM
            und FTUI Charts erstellen.</li>        
        </ul> 
</ul>

=end html_DE
=cut
