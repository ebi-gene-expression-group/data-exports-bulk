
FROM openjdk:12-oraclelinux7 as build
RUN yum update -y && yum install -y git && yum install -y wget
RUN git clone https://github.com/schibsted/jslt.git
RUN wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && mv /jq-linux64 /jq && chmod +x /jq
COPY ./jslt/MultiLineJSLT.java /jslt/core/src/main/java/com/schibsted/spt/data/jslt/cli
WORKDIR jslt
RUN /jslt/gradlew clean shadowJar

FROM adoptopenjdk:15-jre
COPY ./bin/run_schema_transform.sh /src/
COPY --from=build /jslt/core/build/libs/core-0.1.11-all.jar /app/run-jslt.jar
COPY --from=build /jq /bin 



