#!/bin/bash

#"${epochdate},${unfiltered},${filtered},${calibratedBG}" >> ./noise-input.csv
# calculate the noise from csv input (format shown above) and put the noise in ./noise.json
# calculated noise is a floating point number from 0 to 1 where 0 is the cleanest and 1 is the noisiest
#
# Calculate the sum of the distance of all points (overallDistance)
# Calculate the overall distance of between the first and last point (sod)
# Calculate noise as the following formula 1 - sod/overallDistance
# noise will get closer to zero as the sum of the individual lines are mostly in a straight or straight moving curve
# noise will get closer to one as the sum of the distance of the individual lines gets large 
# also added multiplier to get more weight to the latest BG values
# also added weight for points where the delta shifts from pos to neg or neg to pos (peaks/valleys)
# the more peaks and valleys, the more noise is amplified

INPUT=${1:-"${HOME}/myopenaps/monitor/xdripjs/noise-input41.csv"}
OUTPUT=${2:-"${HOME}/myopenaps/monitor/xdripjs/noise.json"}
MAXRECORDS=12
MINRECORDS=4
noise=0

function ReportNoiseAndExit()
{
  echo "[{\"noise\":$noise}]" > $OUTPUT
  cat $OUTPUT
  exit
}

if [ -e $INPUT ]; then
  yarr=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f2 ) )
  xdate=( $(tail -$MAXRECORDS $INPUT | cut -d ',' -f1 ) )
  n=${#yarr[@]}
else
  noise=0
  ReportNoiseAndExit
fi

#    set initial x values based on date differences

if [ $(bc <<< "$n < $MINRECORDS") -eq 1 ]; then
  # set noise = 0 - unknown
  noise=0
	#echo "noise = 0 no records"
  ReportNoiseAndExit
fi

firstDate=${xdate[0]}
for (( i=0; i<$n; i++ ))
do
  xarr[$i]=$(bc -l <<< "(${xdate[$i]} - $firstDate) / 15") 
#  echo "x,y=${xarr[$i]},${yarr[$i]}"
done

#echo ${xarr[@]}
#echo ${xdate[@]}
#echo ${yarr[@]}

# sod = sum of distances
sod=0
overallDistance=0

lastDelta=0
for (( i=1; i<$n; i++ ))
do
  # time-based multiplier 
  # y2y1Delta adds a multiplier that gives 
  # higher priority to the latest BG's
  y2y1Delta=$(bc -l  <<< "(${yarr[$i]} - ${yarr[$i-1]}) * (1 +  $i/($n * 4))")
  x2x1Delta=$(bc -l <<< "${xarr[$i]} - ${xarr[$i-1]}")
  #echo "x delta=$x2x1Delta, y delta=$y2y1Delta" 
  if [ $(bc -l <<< "$lastDelta > 0") -eq 1 -a $(bc <<< "$y2y1Delta < 0") -eq 1 ]; then
    # for this single point, bg switched from positive delta to negative, increase noise impact  
    # this will not effect noise to much for a normal peak, but will increase the overall noise value
    # in the case that the trend goes up/down multiple times such as the bounciness of a dying sensor's signal 
    y2y1Delta=$(bc -l <<< "${y2y1Delta} * 1.3")
  elif [ $(bc -l <<< "$lastDelta < 0") -eq 1 -a $(bc -l <<< "$y2y1Delta > 0") -eq 1 ]; then
    # switched from negative delta to positive, increase noise impact 
    # in this case count the noise a bit more because it could indicate a big "false" swing upwards which could
    # be troublesome if it is a false swing upwards and a loop algorithm takes it into account as "clean"
    y2y1Delta=$(bc -l <<< "${y2y1Delta} * 1.4")
  fi
  lastDelta=$y2y1Delta

  #echo "yDelta=$y2y1Delta, xDelta=$x2x1Delta"
  sod=$(bc  -l <<< "$sod + sqrt(($x2x1Delta)^2 + ($y2y1Delta)^2)")
done  

overallDistance=$(bc -l <<< "sqrt((${yarr[$n-1]} - ${yarr[0]})^2 + (${xarr[$n-1]} - ${xarr[0]})^2)")

if [ $(bc -l <<< "$sod == 0") -eq 1 ]; then
  # assume no noise if no records
  noise = 0
	#echo "noise = sod == 0"
else
  #echo "sod=$sod, overallDistance=$overallDistance"
  noise=$(bc -l <<< "1 - ($overallDistance/$sod)")
	#echo "noise = $noise"
fi
noise=$(printf "%.*f\n" 5 $noise)
ReportNoiseAndExit
