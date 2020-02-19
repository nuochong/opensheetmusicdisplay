#!/bin/bash
# This script runs a visual regression test on all the images
# generated from OSMD samples (npm run generate:current and npm run generate:blessed)
#
#   inspired by and adapted from Vexflow's visual regression tests.
#
# Prerequisites: ImageMagick
#
# On OSX:   $ brew install imagemagick
# On Linux: $ apt-get install imagemagick
#
# Usage:
#
#
#  First generate the known good or previous state PNG images you want to compare to, e.g. the develop branch or last release:
#    (Server has to be running for this: npm start)
#
#    npm run generate:blessed
#
#  Make changes in OSMD, then generate your new images:
#
#    npm run generate:current
#
#  Run the regression tests against the blessed images in tests/blessed.
#
#    npm run test:visual
#    # npm will navigate to the base folder automatically
#
#    # or: (this should be done from the main OSMD folder)
#    # sh test/Util/visual_regression.sh
#
#  Check visual_regression/diff/results.txt for results. This file is sorted
#  by PHASH difference (most different files on top.) The composite diff
#  images for failed tests (i.e., PHASH > 1.0) are stored in visual_regression/diff.
#
#  If you are satisfied with the differences, copy *.png from visual_regression/current
#  into visual_regression/blessed, and submit your change.

# PNG viewer on OSX. Switch this to whatever your system uses.
# VIEWER=open

# Show images over this PHASH threshold. This is probably too low, but
# a good first pass.
THRESHOLD=0.01

# Directories. You might want to change BASE, if you're running from a
# different working directory. (only necessary if you're running the script manually, i.e. not from npm run test:visual)
if [ "$1" == "" ]
then
  BASEFOLDER="./visual_regression"
else
  BASEFOLDER=$1
fi
BLESSED=$BASEFOLDER/blessed
CURRENT=$BASEFOLDER/current
DIFF=$BASEFOLDER/diff

# All results are stored here.
RESULTS=$DIFF/results.txt
WARNINGS=$DIFF/warnings.txt

# If no prefix is provided, test all images.
if [ "$2" == "" ]
then
  files=*.png
else
  files=$2*.png
  printf "only processing images matching bash string (not regex): ${files}\n"
fi

# some sanity checks: check if some png images are in the right folder and warn if not. doesn't make sure there are actual, correct png images though.
folderWarningStringMsg="Also, please run this npm script from the base OSMD folder. (npm run test:visual should do this automatically)
    Exiting without running visual regression tests.\n"
# check if current directory exists / started from base OSMD folder
if [ ! -e "$CURRENT" ]
then
  printf "Warning: directory ${CURRENT} missing. Please run npm run generate:current (and if necessary npm run generate:blessed) first.
    ${folderWarningStringMsg}"
  exit 1
fi
# check if blessed directory exists / started from base OSMD folder
if [ ! -e "$BLESSED" ]
then
  printf "Warning: directory ${BLESSED} missing. Please run npm run generate:blessed first (or otherwise get the blessed images).
    ${folderWarningStringMsg}"
  exit 1
fi
# note: ls returns errors if the directory doesn't exist
totalCurrentImages=`ls -l $CURRENT/*.png | wc -l | sed 's/[[:space:]]//g'`
totalBlessedImages=`ls -l $BLESSED/*.png | wc -l | sed 's/[[:space:]]//g'`
# check if there are some current images
if [ "$totalCurrentImages" -lt 1 ]
then
  printf "Warning: Found no pngs in ${CURRENT}. Please run npm run generate (and if necessary npm run blessed) first.
    ${folderWarningStringMsg}"
  exit 1
fi
# check if there are some blessed images
if [ "$totalBlessedImages" -lt 1 ]
then
  printf "Warning: Found no pngs in ${BLESSED}. Please run npm run blessed first, ideally on the repository's develop state.
    ${folderWarningStringMsg}"
  exit 1
fi
# check that #currentImages == #blessedImages (will continue anyways)
if [ ! "$totalCurrentImages" -eq "$totalBlessedImages" ]
then
  printf "Warning: Number of current images (${totalCurrentImages}) is not the same as blessed images (${totalBlessedImages}). Continuing anyways.\n"
else
  printf "Found ${totalCurrentImages} current and ${totalBlessedImages} blessed png files (not tested if valid). Continuing.\n"
fi

mkdir -p $DIFF
if [ -e "$RESULTS" ]
then
  rm $DIFF/*
fi
touch $RESULTS
touch $RESULTS.pass
touch $RESULTS.fail
touch $WARNINGS

# Number of simultaneous jobs
nproc=$(sysctl -n hw.physicalcpu 2> /dev/null || nproc)
if [ -n "$NPROC" ]; then
  nproc=$NPROC
fi

total=`ls -l $BLESSED/$files | wc -l | sed 's/[[:space:]]//g'`

echo "Running $total tests with threshold $THRESHOLD (nproc=$nproc)..."

function ProgressBar {
    let _progress=(${1}*100/${2}*100)/100
    let _done=(${_progress}*4)/10
    let _left=40-$_done
    _fill=$(printf "%${_done}s")
    _empty=$(printf "%${_left}s")

    printf "\rProgress : [${_fill// /#}${_empty// /-}] ${_progress}%%"
}

function diff_image() {
  local image=$1
  local name=`basename $image .png`
  local blessed=$BLESSED/$name.png
  local current=$CURRENT/$name.png
  local diff=$current-temp

  if [ ! -e "$current" ]
  then
    echo "Warning: $name.png missing in $CURRENT." >$diff.warn
    return
  fi

  if [ ! -e "$blessed" ]
  then
    return
  fi

  cp $blessed $diff-a.png
  cp $current $diff-b.png

  # Calculate the difference metric and store the composite diff image.
  local hash=`compare -metric PHASH -highlight-color '#ff000050' $diff-b.png $diff-a.png $diff-diff.png 2>&1`

  local isGT=`echo "$hash > $THRESHOLD" | bc -l`
  if [ "$isGT" == "1" ]
  then
    # Add the result to results.text
    echo $name $hash >$diff.fail
    # Threshold exceeded, save the diff and the original, current
    cp $diff-diff.png $DIFF/$name.png
    cp $diff-a.png $DIFF/$name'_'Blessed.png
    cp $diff-b.png $DIFF/$name'_'Current.png
    echo
    echo "Test: $name"
    echo "  PHASH value exceeds threshold: $hash > $THRESHOLD"
    echo "  Image diff stored in $DIFF/$name.png"
    # $VIEWER "$diff-diff.png" "$diff-a.png" "$diff-b.png"
    # echo 'Hit return to process next image...'
    # read
  else
    echo $name $hash >$diff.pass
  fi
  rm -f $diff-a.png $diff-b.png $diff-diff.png
}

function wait_jobs () {
  local n=$1
  while [[ "$(jobs -r | wc -l)" -ge "$n" ]] ; do
     # echo ===================================== && jobs -lr
     # wait the oldest job.
     local pid_to_wait=`jobs -rp | head -1`
     # echo wait $pid_to_wait
     wait $pid_to_wait  &> /dev/null
  done
}

count=0
for image in $CURRENT/$files
do
  count=$((count + 1))
  ProgressBar ${count} ${total}
  wait_jobs $nproc
  diff_image $image &
done
wait

cat $CURRENT/*.warn 1>$WARNINGS 2>/dev/null
rm -f $CURRENT/*.warn

## Check for files newly built that are not yet blessed.
for image in $CURRENT/$files
do
  name=`basename $image .png`
  blessed=$BLESSED/$name.png
  current=$CURRENT/$name.png

  if [ ! -e "$blessed" ]
  then
    echo "  Warning: $name.png missing in $BLESSED." >>$WARNINGS
  fi
done

num_warnings=`cat $WARNINGS | wc -l`

cat $CURRENT/*.fail 1>$RESULTS.fail 2>/dev/null
num_fails=`cat $RESULTS.fail | wc -l`
rm -f  $CURRENT/*.fail

# Sort results by PHASH
sort -r -n -k 2 $RESULTS.fail >$RESULTS
sort -r -n -k 2 $CURRENT/*.pass 1>>$RESULTS 2>/dev/null
rm -f $CURRENT/*.pass $RESULTS.fail $RESULTS.pass

echo
echo Results stored in $DIFF/results.txt
echo All images with a difference over threshold, $THRESHOLD, are
echo available in $DIFF, sorted by perceptual hash.
echo

if [ "$num_warnings" -gt 0 ]
then
  echo
  echo "You have $num_warnings warning(s):"
  cat $WARNINGS
fi

if [ "$num_fails" -gt 0 ]
then
  echo "You have $num_fails fail(s):"
  head -n $num_fails $RESULTS
else
  echo "Success - All diffs under threshold!"
fi
