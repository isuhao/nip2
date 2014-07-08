#!/bin/sh

# set -x

top_srcdir=$1
tmp=$top_srcdir/test/tmp
test_images=$top_srcdir/test/images
image=$test_images/slanted_oval_vase2.jpg

# the matlab image and reference image
matlab=$test_images/lena.mat
matlab_ref=$test_images/lena.tif

# make a mono image
vips im_extract_band $image $tmp/mono.v 1
mono=$tmp/mono.v

# make a radiance image
vips im_float2rad $image $tmp/rad.v 
rad=$tmp/rad.v

# make a cmyk image
vips im_bandjoin $image $tmp/mono.v $tmp/t1.v
vips im_copy_set $tmp/t1.v $tmp/cmyk.v 15 1 1 0 0 
cmyk=$tmp/cmyk.v

# save to t1.format, load as back.v
save_load() {
	in=$1
	format=$2
	mode=$3

	if ! vips im_copy $in $tmp/t1.$format$mode ; then
		echo "write to $out failed"
		exit 1
	fi

	if ! vips im_copy $tmp/t1.$format $tmp/back.v ; then
		echo "read from $out failed"
		exit 1
	fi
}

# is a difference beyond a threshold? return 0 (meaning all ok) or 1 (meaning
# error, or outside threshold)
# 
# use bc since bash does not support fp math
break_threshold() {
	diff=$1
	threshold=$2
	return $(echo "$diff <= $threshold" | bc -l)
}

# subtract, look for max difference less than a threshold
test_difference() {
	before=$1
	after=$2
	threshold=$3

	vips im_subtract $before $after $tmp/difference.v
	vips im_abs $tmp/difference.v $tmp/abs.v 
	dif=`vips im_max $tmp/abs.v`

	if break_threshold $dif $threshold; then
		echo "save / load difference is $dif"
		exit 1
	fi
}

# save to the named file in tmp, convert back to vips again, subtract, look
# for max difference less than a threshold
test_format() {
	in=$1
	format=$2
	threshold=$3
	mode=$4

	echo -n "testing $(basename $in) $format$mode ... "

	save_load $in $format $mode
	test_difference $in $tmp/back.v $threshold

	echo "ok"
}

# as above, but hdr format
# this is a coded format, so we need to rad2float before we can test for
# differences
test_rad() {
	in=$1

	echo -n "testing $(basename $in) hdr ... "

	save_load $in hdr

	vips im_rad2float $in $tmp/before.v
	vips im_rad2float $tmp/back.v $tmp/after.v

	test_difference $tmp/before.v $tmp/after.v 0

	echo "ok"
}

# as above, but raw format
# we can't use suffix stuff to pick the load/save
test_raw() {
	in=$1

	echo -n "testing $(basename $in) raw ... "

	vips copy $in $tmp/before.v
	width=`vips im_header_int Xsize $tmp/before.v`
	height=`vips im_header_int Ysize $tmp/before.v`
	bands=`vips im_header_int Bands $tmp/before.v`

	vips rawsave $tmp/before.v $tmp/raw
	vips rawload $tmp/raw $tmp/after.v $width $height $bands

	test_difference $tmp/before.v $tmp/after.v 0

	echo "ok"
}

# a format for which we only have a load (eg. matlab)
# pass in a reference file as well and compare to that
test_loader() {
	ref=$1
	in=$2
	format=$3

	echo -n "testing $(basename $in) $format ... "

	vips copy $ref $tmp/before.v
	vips copy $in $tmp/after.v

	test_difference $tmp/before.v $tmp/after.v 0

	echo "ok"
}

test_format $image v 0
test_format $image tif 0
test_format $image tif 15 :jpeg
test_format $image tif 0 :deflate
test_format $image tif 0 :packbits
test_format $image tif 15 :jpeg,tile
test_format $image tif 15 :jpeg,tile,pyramid
test_format $image png 0
test_format $image png 0 :9,1
test_format $image jpg 15
test_format $image ppm 0
test_format $image pfm 0
test_format $image fits 0

# csv can only do mono
test_format $mono csv 0

# cmyk jpg is a special path
test_format $cmyk jpg 15
test_format $cmyk tif 0
test_format $cmyk tif 15 :jpeg
test_format $cmyk tif 15 :jpeg,tile
test_format $cmyk tif 15 :jpeg,tile,pyramid

test_rad $rad 

test_raw $mono 
test_raw $image 

test_loader $matlab_ref $matlab matlab

# we have loaders but not savers for other formats, add tests here

