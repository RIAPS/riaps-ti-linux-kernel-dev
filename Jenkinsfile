pipeline {
  agent any
  options {
    buildDiscarder logRotator(daysToKeepStr: '30', numToKeepStr: '10')
  }
  stages {
    stage('build') {
      steps {
        sh 'chmod +x riaps_build.sh'
        sh './riaps_build.sh'
      }
    }
  }
  post {
    success {
      archiveArtifacts artifacts: 'deploy/*.deb', fingerprint: true
    }
  }
}