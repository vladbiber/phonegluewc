#!/bin/sh
# enc2.sh NAME W H KBIT PRESET SECS FPS: back camera through x264 for SECS at FPS
(bwrap --dev-bind / / --tmpfs /dev/dma_heap timeout -s INT $6 gst-launch-1.0 -e -q libcamerasrc camera-name="/base/soc@0/cci@ac4b000/i2c-bus@0/camera@2d" ! video/x-raw,width=$2,height=$3 ! tee name=t t. ! queue leaky=downstream max-size-buffers=2 ! fakesink t. ! queue leaky=downstream max-size-buffers=8 ! videoconvert n-threads=4 ! video/x-raw,format=I420 ! x264enc speed-preset=$5 bitrate=$4 key-int-max=30 threads=6 ! h264parse ! queue ! mux. mp4mux name=mux ! filesink location=/tmp/e_$1.mp4 2>&1 | grep -v -E "INFO|WARN|rectangle") &
sleep 2; ~/camtest/app/phonecam-raw --fps back $7; sleep $(($6 - 5)); cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1; wait
