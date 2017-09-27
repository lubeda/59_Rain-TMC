 use LWP::Simple;
 use Data::Dumper;
use JSON;
use warnings;
use strict;
  
my $data = get("https://api.themeteocompany.com/precipitation/getforecastbylatlon/?radius=0&lat=51.65&lon=7.32");

if ($data){
print $data;      

}
else
{print "jkfjskldflsf";}
    
    

    exit;
    $data = decode_json($data);

        my @array = @{$data->{ForecastResult}};

        foreach my $a (@array) {

          my $rain = $a->{Value};

            my $timestamp = $a->{TimeStamp};
            $timestamp =~ /\(([0-9]*)\)/ ;
            $timestamp = $1;
            print ($rain . " " . $timestamp ."\n");    
        }


exit;
