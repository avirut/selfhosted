#!/bin/bash
apt-get update
apt-get install restic
restic self-update
restic version