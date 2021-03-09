FROM openjdk:12-oraclelinux7
RUN git clone https://github.com/schibsted/jslt.git
CMD /jslt/gradlew clean shadowJar


FROM openjdk:12-oraclelinux7
COPY ./bin/run_schema_transform.sh /src/
COPY ./jslt/core/build/libs/core-0.1.11-all.jar /app/run-jslt.jar
RUN yum update -y && yum install jq -y
CMD /src/run_schema_transform.sh

