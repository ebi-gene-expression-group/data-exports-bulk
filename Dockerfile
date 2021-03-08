FROM openjdk:11
RUN git clone https://github.com/schibsted/jslt.git
CMD /jslt/gradlew clean shadowJar

FROM openjdk:11-jre-slim
COPY ./bin/run_schema_transform.sh /src/
COPY ./jslt/core/build/libs/core-0.1.11-all.jar /app/run-jslt.jar
CMD /src/run_schema_transform.sh 

