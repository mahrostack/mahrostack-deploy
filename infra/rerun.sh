#!/bin/bash



docker compose down $1 && docker compose up $1 -d --build && docker exec edge-nginx nginx -s reload
