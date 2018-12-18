#!/bin/bash

# framework
# agent
# role
# offers(?)

# framework - prints framework options
# framework list - prints frameworks (fmt: name - id)
# framework <framework-id> agents
# framework <framework-id> roles
#
# agent - prints agent options
# agent list - prints agents (fmt: hostname - id)
# agent <agent-id> - prints info about a particular agent (opts: {{used,free,reserved}resources, roles, frameworks})

#####
# Pre-flight checks
#####
# Check for jq
if [[ -z $(which jq) ]]; then
  echo "ERROR: 'jq' not found. Please install jq and add it to your PATH to continue."
  exit
# Check that current dir is a bundle dir
elif [[ $(pwd) != *"bundle"* ]]; then
  echo "ERROR: The working directory, $(pwd), doesn't seem to be a bundle directory. Please verify the working directory name contains 'bundle'."
  exit
# Ensure at least one master folder exists
elif [[ $(ls -l | grep -i 'master') != *"master"* ]]; then
  echo "ERROR: Unable to find a directory containing the name 'master'. Please ensure that the folder containing the master state files and logs is a name contains the string 'master'."
  exit
fi

#####
# Find the leading Mesos master directory
#####
# WIP NEED TO ADD A CHECK THAT HOSTNAME ISN'T NULL!
# echo "ERROR: Hostname field empty. Please verify that ${MESOS_LEADER_DIR}/5050-registrar_1__registry.json has valid information."
for i in $(find ./*master* -type f -name 5050-registrar_1__registry.json); do
  if [[ ! -z $(jq '.master.info.hostname' $i | grep -vi 'null\|\[\|\]' | cut -d '"' -f 2) ]]; then
    # Set the Mesos leader hostname
    MESOS_LEADER_HOSTNAME="$(jq '.master.info.hostname' $i | grep -vi 'null\|\[\|\]' | cut -d '"' -f 2 | uniq)"
    # Check if somehow we're seeing multiple leading masters
    if [[ ! -z $(echo $MESOS_LEADER_HOSTNAME | awk '{print $2}') ]]; then
      echo -e "ERROR: Detected multiple entries for the leading Mesos master. Please address these issues. The hostnames found were:\n ${MESOS_LEADER_HOSTNAME}"
      exit
    fi
    # Set the Mesos leader dir based on HOSTNAME_master format
    MESOS_LEADER_DIR="$(pwd)/${MESOS_LEADER_HOSTNAME}_master"
    # Verify the Mesos leader dir exists (this could be done better)
    if [[ -z $(ls -l $MESOS_LEADER_DIR | grep -vi 'no such') ]]; then
      echo "ERROR: Couldn't find a the leading Mesos master directory within this directory. Expected path: ${MESOS_LEADER_DIR}"
      exit
    fi
  fi
done

#####
# Framework
#####
# WIP
if [[ $1 == "framework" && $# -eq 1 ]]; then
  # If naked, print usage
  if [[ $# -eq 1 ]]; then
    echo "Print framework usage here, etc."
  fi
elif [[ $1 == "framework" && $# -eq 2 ]]; then
  # Framework list
  if [[ $2 == "list" ]]; then
    echo -e "ID NAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
    jq -r '.frameworks[] | "\(.id) \(.name)"' $MESOS_LEADER_DIR"/5050-master_state-summary.json" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  # Print framework summary for a given framework name
  elif [[ $2 == "$(jq -r '.frameworks[] | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_state-summary.json" | grep -i $2)" ]]; then
    jq '.frameworks[] | select(.name == "'$2'")' $MESOS_LEADER_DIR"/5050-master_state-summary.json"
  # If there are no matches for parameter(s) print error and usage
  else
    echo "ERROR: Command not found."
    echo "Print framework usage here, etc."
  fi
fi

#####
# Agent
#####
# WIP
if [[ $1 == "agent" && $# -eq 1 ]]; then
  # If naked, print usage
  if [[ $# -eq 1 ]]; then
    echo "Print agent usage here, etc."
  fi
elif [[ $1 == "agent" && $# -eq 2 ]]; then
  # Agent list
  if [[ $2 == "list" ]]; then
    echo -e "ID HOSTNAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
    jq -r '.slaves[] | "\(.id) \(.hostname)"' $MESOS_LEADER_DIR"/5050-master_state-summary.json" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  # If there are no matches for parameter(s) print error and usage
  else
    echo "ERROR: Command not found."
    echo "Print framework usage here, etc."
  fi
fi

#####
# Role
#####
# WIP
if [[ $1 == "role" && $# -eq 1 ]]; then
  # If naked, print usage
  if [[ $# -eq 1 ]]; then
    echo "Print role usage here, etc."
  fi
elif [[ $1 == "role" && $# -eq 2 ]]; then
  # Agent list
  if [[ $2 == "list" ]]; then
    echo -e "NAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
    jq -r '.roles[] | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_roles.json" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  # Print framework summary for a given framework name
  elif [[ $2 == "$(jq -r '.roles[] | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_roles.json" | grep -i $2)" ]]; then
    jq '.roles[] | select(.name == "'$2'")' $MESOS_LEADER_DIR"/5050-master_roles.json"
  # If there are no matches for parameter(s) print error and usage
  else
    echo "ERROR: Command not found."
    echo "Print framework usage here, etc."
  fi
fi





# echo "nonexit"
# echo "nonexit"
# echo "nonexit"
# echo "nonexit"
# echo "nonexit"



#### fix things
