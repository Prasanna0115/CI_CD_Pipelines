pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    triggers {
        githubPush()
    }

    environment {
        PYTHON = 'python3'
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    if (!(params.AWS_REGION ==~ /[a-z]{2}(-gov)?-[a-z]+-[0-9]/)) {
                        error('AWS_REGION must be a valid region name such as ap-south-1.')
                    }
                    if (!(params.AWS_ACCOUNT_ID ==~ /[0-9]{12}/)) {
                        error('AWS_ACCOUNT_ID must contain exactly 12 digits.')
                    }
                    if (!(params.ECR_REPOSITORY ==~ /[a-z0-9]+([._\/-][a-z0-9]+)*/)) {
                        error('ECR_REPOSITORY contains unsupported characters.')
                    }
                    if (!(params.EC2_HOST ==~ /[A-Za-z0-9.-]+/)) {
                        error('EC2_HOST must be a DNS name or IPv4 address without a username.')
                    }
                    if (!(params.APP_PORT ==~ /[0-9]{1,5}/) ||
                        params.APP_PORT.toInteger() < 1 ||
                        params.APP_PORT.toInteger() > 65535) {
                        error('APP_PORT must be an integer from 1 to 65535.')
                    }
                    checkout scm
                    env.IMAGE_TAG = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    env.VALIDATION_CONTAINER = "cicd-fastapi-validation-${env.BUILD_NUMBER}"
                    echo "Checked out commit ${env.IMAGE_TAG}"
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    set -eu
                    "$PYTHON" --version
                    "$PYTHON" -m venv .venv
                    .venv/bin/python -m pip install --upgrade pip
                    .venv/bin/python -m pip install -r requirements-dev.txt
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu
                    mkdir -p reports
                    .venv/bin/python -m pytest --junitxml=reports/pytest.xml
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    set -eu
                    IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"
                    docker build --pull --tag "$IMAGE_URI" .
                    echo "Built image $IMAGE_URI"
                '''
            }
        }

        stage('Docker Validation') {
            steps {
                sh '''
                    set -eu
                    IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"
                    docker run --detach \
                        --name "$VALIDATION_CONTAINER" \
                        --publish 127.0.0.1::8000 \
                        --env "APP_VERSION=${IMAGE_TAG}" \
                        "$IMAGE_URI"

                    HOST_PORT="$(docker port "$VALIDATION_CONTAINER" 8000/tcp | sed 's/.*://')"
                    for attempt in $(seq 1 30); do
                        if curl --fail --silent "http://127.0.0.1:${HOST_PORT}/health"; then
                            printf '\\nContainer health check passed.\\n'
                            exit 0
                        fi
                        sleep 2
                    done

                    docker logs "$VALIDATION_CONTAINER"
                    echo 'Container did not become healthy within 60 seconds.' >&2
                    exit 1
                '''
            }
        }

        stage('Deployment') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'EC2_SSH_KEY', usernameVariable: 'EC2_SSH_USER'),
                    file(credentialsId: 'ec2-known-hosts', variable: 'SSH_KNOWN_HOSTS')
                ]) {
                    sh '''
                        set -eu
                        set +x
                        export AWS_DEFAULT_REGION="$AWS_REGION"

                        REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                        IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
                        aws ecr get-login-password --region "$AWS_REGION" |
                            docker login --username AWS --password-stdin "$REGISTRY"
                        docker push "$IMAGE_URI"
                        echo "Pushed image $IMAGE_URI"

                        ssh -i "$EC2_SSH_KEY" \
                            -o BatchMode=yes \
                            -o IdentitiesOnly=yes \
                            -o StrictHostKeyChecking=yes \
                            -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS" \
                            "$EC2_SSH_USER@$EC2_HOST" \
                            "AWS_REGION='$AWS_REGION' AWS_ACCOUNT_ID='$AWS_ACCOUNT_ID' ECR_REPOSITORY='$ECR_REPOSITORY' IMAGE_TAG='$IMAGE_TAG' APP_PORT='$APP_PORT' bash -s" \
                            < scripts/deploy_ec2.sh
                    '''
                }
            }
        }

        stage('Post-Deployment Verification') {
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'EC2_SSH_KEY', usernameVariable: 'EC2_SSH_USER'),
                    file(credentialsId: 'ec2-known-hosts', variable: 'SSH_KNOWN_HOSTS')
                ]) {
                    sh '''
                        set -eu
                        ssh -i "$EC2_SSH_KEY" \
                            -o BatchMode=yes \
                            -o IdentitiesOnly=yes \
                            -o StrictHostKeyChecking=yes \
                            -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS" \
                            "$EC2_SSH_USER@$EC2_HOST" \
                            "curl --fail --silent --show-error http://127.0.0.1:${APP_PORT}/health"
                        printf '\\nPost-deployment health check passed.\\n'
                    '''
                }
            }
        }
    }

    post {
        always {
            junit testResults: 'reports/pytest.xml', allowEmptyResults: true
            archiveArtifacts artifacts: 'reports/pytest.xml', allowEmptyArchive: true
            sh '''
                if [ -n "${VALIDATION_CONTAINER:-}" ]; then
                    docker rm --force "$VALIDATION_CONTAINER" >/dev/null 2>&1 || true
                fi
                rm -rf .venv
            '''
        }
    }
}
