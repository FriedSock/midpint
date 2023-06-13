FROM amazoncorretto:19

ENV OTP_VERSION=1.5.0

RUN yum install -y unzip

ADD https://repo1.maven.org/maven2/org/opentripplanner/otp/$OTP_VERSION/otp-$OTP_VERSION-shaded.jar /usr/local/share/java/

RUN ln -s otp-$OTP_VERSION-shaded.jar /usr/local/share/java/otp.jar

COPY otp /usr/local/bin/

RUN mkdir /graphs
RUN mkdir /graphs/current
COPY london.osm.pbf /graphs/current/london.pbf
COPY gtfs/gtfs.zip /graphs/current/gtfs.zip

COPY otp-config.json /graphs/current/otp-config.json

ENV JAVA_OPTIONS=-Xmx13G

CMD ["otp", "--build", "/graphs/current", "--inMemory"]
