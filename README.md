# midpint

It finds the midpint

There are three subdirectories, which may become their own repos but for now it is a monorepo.

## otp
This directory houses a dockerfile for running OpenTripPlanner for london, with the goal of being able to generate isochrones that we can then intersect to find areas where nice pubs might be.

## tflgtfs-rb
This is where we generate GTFS data for transport for london, loosely based off https://github.com/CommuteStream/tflgtfs

## web
The code for the website that will show the map and let users pick some points to find the midpint between them.
