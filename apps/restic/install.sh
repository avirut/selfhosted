#!/bin/bash
apt-get update
apt-get install restic
apt-get upgrade restic
restic self-update
restic version