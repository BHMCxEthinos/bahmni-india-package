#!/bin/bash

docker compose down -v bunkerweb bw-scheduler
docker compose up -d bunkerweb bw-scheduler

