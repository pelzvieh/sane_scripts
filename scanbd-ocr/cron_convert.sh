#!/bin/bash
# (c) 2015 Andreas Feldner
# Licensed under GPL 3, c.f. accompanying documentation
# configure base_url below, then remove the following line
echo "!! CONFIGURATION REQUIRED !!" >&2 ; exit 2

# the idea is that you prepare some web collaboration (in my case nextcloud) in a way
# that files put to subfolders of $base_dir/scans will appear as the same subfolders
# of $base_url. You can achieve this by a suitable dav2fs mount from your collaboration
# application to $base_dir/scans.
# $base_dir/work will be created by the script and be used to prepare the resulting
# PDFs with OCR layer. It should not be mounted to your collaboration application
# as the file operations might interfere inefficiently with any version tracking.
# 
base_url="https://example.com/nextcloud/remote.php/webdav/Scans/"
# this should be OK. If you re-configure, do so in all scripts of this package.
base_dir="/var/lib/saned"

# logging
tag="scanbd $0"

# check pid
pid_file="${base_dir}/.cron_convert.pid"
test -r $pid_file && kill -0 $( cat $pid_file ) 2>/dev/null && { echo "cron_convert already running" >&2; logger -t "$tag" "Detected running instance"; exit 0; }

# write pid file
echo $$ > $pid_file

function handle_input_dir() {
	input_dir="$1"

        # test if directory exists
        test -d "$input_dir" || { logger -t "$tag" "Requested input dir $input_dir does not exist"; return; }

	# Output dir of scan process
	output_dir=$(mktemp -d ${base_dir}/work/$(date +%F)_XXXX)
	repository_dir=${output_dir/work/scans}

	# test if directory exists
	test -d "$output_dir" || { logger -t "$tag" "Requested output dir $output_dir does not exist"; return; }

	# Resultfiles
	result_file="$output_dir/alle.pdf"
	result_file_fax="$output_dir/alle-fax.pdf"

	# loop over the files contained in directory until nothing new is found
	# reason: the conversion might well be slower than scanning of a new page
	until test -f "$result_file" && test -z "$(find "$input_dir" -name "*.png" -newer "$result_file")"; do
	  logger -t "$tag" "starting a conversion batch"
	  # remember the timestamp to set on the created files
	  conversion_time=$(date +%Y%m%d%H%M)

	  # move image files to target directory
	  mv "$input_dir"/*.png "$output_dir"/ || { logger -t "$tag" "Could not move png files to work directory"; return; }

	  # iterate through the pngs, creating one searchable PDF for each
	  for file in $output_dir/*.png;do
	    pageoutfile="${file%.*}-page.pdf"
	    logger -t "$tag" "converting $file to $pageoutfile"
	    [ "$file" -nt "$pageoutifle" ] && { tesseract -l deu "$file" stdout pdf > "$pageoutfile" || rm "$pageoutfile" ; }
	  done
	  logger -t "$tag" "completed a conversion batch"

	  # combine the pdfs using ghostscript
	  logger -t "$tag" "Combining pages to one file"
	  gs -dCompatibilityLevel=1.4 -dNOPAUSE -dQUIET -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite "-sOutputFile=$result_file" "$output_dir"/*-page.pdf

	done

	# exit if nothing was done
	test -z "$conversion_time" && { logger -t "$tag" "No new files found"; exit 0; }

	# create a low-res version
	logger -t "$tag" "Creating low-res fax version"
	convert -density 200 "$result_file" -monochrome -threshold 80% -despeckle "$result_file_fax"

	# re-set timestamp on created result files
	logger -t "$tag" "All work done, finalising"
	touch -t "$conversion_time" "$result_file"
	touch -t "$conversion_time" "$result_file_fax"

	# move finished work into repository
	mv "${output_dir}" "${repository_dir}" || { logger -t "$tag" "Could not move result of work to repository ${repository_dir}" ; return; }

	echo "Scan resulats are converted to ${base_url}$(basename $output_dir)/$(basename $result_file) and ${base_url}$(basename $output_dir)/$(basename $result_file_fax). Remember to download within one week." | mail -s "Scan results" saned
	rmdir "$input_dir" || logger -t "$tag" "Could not remove input dir of closed scans"
}

# Input dir of scan process
input_dirs="${base_dir}/closed_*"
for input_dir in $input_dirs; do
  # remove directory if it is impty
  [ -d "$input_dir" ] && rmdir --ignore-fail-on-non-empty "$input_dir"
  # handle directory if it still exists
  [ -d "$input_dir" ] && handle_input_dir $input_dir
done

logger -t "$tag" "Finished handling closed scan directories"

# remove pid file
rm -f "$pid_file"

exit 0;

