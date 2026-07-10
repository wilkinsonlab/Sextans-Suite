# YARRRML + RMLMapper

# FROM openjdk:18-ea-11-alpine
FROM eclipse-temurin:22_36-jdk-alpine

# Pinned upstream release tags -- bump these deliberately, not silently on every rebuild.
# Check for newer releases: https://github.com/RMLio/yarrrml-parser/tags
#                            https://github.com/RMLio/rmlmapper-java/releases
ARG YARRRML_PARSER_VERSION=1.12.2
ARG RMLMAPPER_JAVA_VERSION=8.1.0

# install everything needed
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache bash nodejs npm wget nmap-ncat maven git && cd / && \
    ########## YARRRML-parser ##########
    wget https://github.com/RMLio/yarrrml-parser/archive/refs/tags/v${YARRRML_PARSER_VERSION}.zip && \
    unzip v${YARRRML_PARSER_VERSION}.zip && rm v${YARRRML_PARSER_VERSION}.zip && \
    mv /yarrrml-parser-${YARRRML_PARSER_VERSION} /yarrrml-parser && \
    cd /yarrrml-parser && \
    # Force known-vulnerable transitive npm deps up to a fixed version (npm's
    # "overrides" field applies regardless of who in the tree requests them).
    # node/npm are already present at this point in the build, so no extra
    # tooling needed to edit the JSON.
    node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync('package.json')); p.dependencies.glob='^11.1.0'; p.overrides={minimatch:'^10.2.3', '@isaacs/brace-expansion':'^5.0.1'}; fs.writeFileSync('package.json', JSON.stringify(p, null, 2));" && \
    npm install --omit=dev && \
    ############# RMLMapper ############
    cd / && \
    wget https://github.com/RMLio/rmlmapper-java/archive/refs/tags/v${RMLMAPPER_JAVA_VERSION}.zip && \
    unzip v${RMLMAPPER_JAVA_VERSION}.zip && rm v${RMLMAPPER_JAVA_VERSION}.zip && \
    mv rmlmapper-java-${RMLMAPPER_JAVA_VERSION} rmlmapper-java && \
    cd rmlmapper-java && \
    # Force known-vulnerable transitive deps up to a fixed version. Maven's
    # "nearest wins" mediation means a version declared directly here beats
    # whatever rmlmapper-java's own transitive deps ask for. Checked against
    # Sextans/Security/vulnerability-register.csv (Image=yrml) -- everything
    # else that register flags for this image was already fixed simply by
    # pinning RMLMAPPER_JAVA_VERSION above to a current release.
    awk '/<dependencies>/{print; \
      print "        <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><version>42.7.13</version></dependency>"; \
      print "        <dependency><groupId>com.fasterxml.jackson.core</groupId><artifactId>jackson-databind</artifactId><version>2.22.1</version></dependency>"; \
      print "        <dependency><groupId>com.fasterxml.jackson.core</groupId><artifactId>jackson-core</artifactId><version>2.22.1</version></dependency>"; \
      print "        <dependency><groupId>com.fasterxml.jackson.core</groupId><artifactId>jackson-annotations</artifactId><version>2.22</version></dependency>"; \
      print "        <dependency><groupId>commons-beanutils</groupId><artifactId>commons-beanutils</artifactId><version>1.11.0</version></dependency>"; \
      next} {print}' pom.xml > pom.xml.patched && mv pom.xml.patched pom.xml && \
    mvn -DskipTests clean package && \
    # map.sh expects the shaded jar at /rmlmapper-java/target/rmlmapper-*all.jar --
    # keep that path but drop everything else the Maven build produced (source,
    # test/compile output, and most importantly the ~250MB local repo cache under
    # /root/.m2, most of which is Maven's own tooling and test-scope-only
    # dependencies that never end up on the runtime classpath).
    mkdir /tmp/jarkeep && mv target/rmlmapper-*-all.jar /tmp/jarkeep/ && \
    cd / && rm -rf rmlmapper-java/target rmlmapper-java/src rmlmapper-java/pom.xml /root/.m2 && \
    mkdir rmlmapper-java/target && mv /tmp/jarkeep/*.jar rmlmapper-java/target/ && rmdir /tmp/jarkeep && \
    # maven/git were only needed to fetch and build rmlmapper-java above
    apk del maven git && \
    mkdir /mnt/data

RUN apk add alpine-sdk ruby ruby-bundler ruby-dev
# Clean APK cache
RUN rm -rf /var/cache/apk/*
RUN mkdir /usr/app
WORKDIR /usr/app
COPY . /usr/app
RUN bundle install && apk del alpine-sdk ruby-dev

RUN chmod a+x entrypoint.sh


ENTRYPOINT ["./entrypoint.sh"]
