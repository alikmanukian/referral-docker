# Referral Factory Encryption - Docker Image Build Files

This repository contains the Dockerfile and associated build files for building the Referral Factory Encryption Docker image.

> **Note**:
> The entire Docker image is built in a rootless environment, meaning that the Docker image is built without the need for root privileges, therefore things like `sudo` will not work - please bear this in mind when making adjustments to the scripts.

## Prerequisites

Before you begin, ensure you have met the following requirements:

`Docker` is installed ad running on your machine. If not, you can download and install Docker from the [official Docker website](https://www.docker.com/products/docker-desktop).

## Structure & Permissions

The Dockerfile will start the process and create the base image, before switching to a rootless user, which will run the entrypoint script `start-app.sh` within `scripts` folder, which does remainder of the setup required to get this running.

## Database

For local testing (not recommended for Production environments), the setup will install and run MariaDB within the image. The database will be created and seeded with the required tables and data. In production environments it is recommended to use an external database.

## Building the Docker Image locally

To build the Docker image locally, run the following command:

```bash
docker build -t referral-factory/encryption:latest .
```

This will create a local tag for the Docker image, which can be used to run the image locally. The tag will be `referral-factory/encryption:latest`.

## Running the Docker Image locally

To run the Docker image locally, create a .env file in a directory of your choosing. The following is an example of a .env file with the minimum required environment variables:

```env
APP_URL=//referrals.mydomain.local
SUPERUSER_EMAIL=youremail@domain.com
REPO_PULL_TOKEN=your_referral_factory_pull_token
APP_KEY=mysupersecretkeyyektercesrepusym
OTP_ENABLED=false
DISABLE_NGINX_PROXY=true
DB_PASSWORD=supersecretpassword
APP_RF_FULL_URL=https://dev.referral-factory.com
```

Other examples of environment variables can be found in the .env.example file in this repository. Reminder that you can also find the [Help Guide](https://help.referral-factory.com/store-your-data-on-your-own-server) here.

> **Note**:
> This .env file is not to be confused with the .env.template file, which is used for the Docker image build process and is required for Laravel to function correctly.

Once you have created your .env file, cd into the directory, and run the following command after building:

```bash
docker run --env-file .env -p 8080:8080 -p 9001:9001 -p 8443:8443 --name 'encryption' referral-factory/encryption:latest
```

This will build and run the Docker image locally, and will enable the app to run from the URL you specified in the .env file at port 8080.

e.g http://referrals.mydomain.local:8080
