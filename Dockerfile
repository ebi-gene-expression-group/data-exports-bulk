FROM openjdk:11
RUN git clone https://github.com/schibsted/jslt.git
COPY ./bin/run_schema_transform.sh /src 

WORKDIR jslt/
CMD ./gradlew clean shadowJar

FROM openjdk:8-jre-slim
COPY ./core/build/libs/core-0.1.11-all.jar /app/run-jslt.jar

RUN run_schema_transform.sh 

