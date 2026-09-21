# syntax=docker/dockerfile:1

# Jenkins controller for the lab: latest LTS on JDK 25 (Debian), plugins baked in, configured
# entirely by JCasC (jenkins/casc/, mounted at /casc by docker-compose.yaml). Runs as the
# base image's non-root `jenkins` user (uid 1000).
#
# 2.568.3 is the newest LTS at the time of writing; bump the tag to upgrade.
FROM docker.io/jenkins/jenkins:2.568.3-lts-jdk25

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# No setup wizard: the admin user and everything else come from JCasC.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/casc
