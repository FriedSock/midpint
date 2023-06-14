FROM amazoncorretto:8

ENV OTP_VERSION=1.5.0

RUN yum install -y unzip

ADD https://repo1.maven.org/maven2/org/opentripplanner/otp/$OTP_VERSION/otp-$OTP_VERSION-shaded.jar /usr/local/share/java/

RUN ln -s otp-$OTP_VERSION-shaded.jar /usr/local/share/java/otp.jar

COPY otp /usr/local/bin/

RUN mkdir /var/otp
RUN mkdir /var/otp/graphs
RUN mkdir /var/otp/graphs/london

COPY vendor/london.osm.pbf /var/otp/graphs/london/london.pbf
COPY vendor/gtfs.zip /var/otp/graphs/london/gtfs.zip
COPY build-config.json /var/otp/graphs/london/build-config.json

ENV JAVA_OPTIONS=-Xmx13G
RUN otp --build /var/otp/graphs/london

CMD ["otp", "--router", "london", "--server"]
