 use LWP::Simple;
 use Data::Dumper;
use JSON;
 
 $content = get("https://api.themeteocompany.com/precipitation/getforecastbylatlon/?&radius=0&lat=51.34&lon=7.4");
 
 $data = decode_json($content);
 
 my $array = $data->{ForecastResult}[434];

$l = 0;

while ($data->{ForecastResult}[$l] != undef)
{
  
  #print "loop";
  #print Dumper($data->{ForecastResult}[$l]->{Value});
  $timestamp = $data->{ForecastResult}[$l]->{TimeStamp};
  $timestamp =~ /\(([0-9]*)\)/ ;
  print $1;
  print "\n";
  
  $l +=1;
}
