#!/bin/bash

# TODO:
########################
# master
# agent
# framework
# role
# offers(?)
#########################
# framework - prints framework options
# framework list - prints frameworks (fmt: name - id)
# framework <framework-id> agents
# framework <framework-id> roles
#########################
# agent - prints agent options
# agent list - prints agents (fmt: hostname - id)
# agent <agent-id> - prints info about a particular agent (opts: {{used,free,reserved}resources, roles, frameworks})
#########################

###
# Need to refactor all of the -ge -eq stuff so that the evaluations aren't repeated
###

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
    MESOS_STATE_SUMMARY="${MESOS_LEADER_DIR}/5050-master_state-summary.json"
    # Verify the Mesos leader dir exists (this could be done better)
    if [[ -z $(ls -l $MESOS_LEADER_DIR | grep -vi 'no such') ]]; then
      echo "ERROR: Couldn't find a the leading Mesos master directory within this directory. Expected path: ${MESOS_LEADER_DIR}"
      exit
    fi
  fi
done

##################################################
##################################################
##################################################
#####
# Framework
#####
# WIP
printFrameworkList () {
  echo -e "ID NAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  jq -r '.frameworks[] | "\(.id) \(.name)"' $MESOS_STATE_SUMMARY | awk '{ printf "%-80s %-40s\n", $1, $2}'
}

printFrameworkIDSummary () {
  jq '.frameworks[] | select(.id == "'$FRAMEWORK_ID'")' $MESOS_STATE_SUMMARY
}

printFrameworkIDAgents () {
  echo -e "ID"
  jq -r '.frameworks[] | select(.id == "'$FRAMEWORK_ID'") | .slave_ids[]' $MESOS_STATE_SUMMARY
}

if [[ $1 == "framework" ]]; then
  if [[ $# -eq 1 ]]; then
    # If naked, print usage
    echo "Print framework usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $# -eq 2 ]]; then
      if [[ $2 == "list" ]]; then
        # Framework list
        printFrameworkList
      elif [[ $2 == "$(jq -r '.frameworks[] | "\(.id)"' $MESOS_STATE_SUMMARY | grep -i $2)" ]]; then
        FRAMEWORK_ID="$2"
        # Print framework summary for a given framework-id
        printFrameworkIDSummary
      else
        # Subcommand/framework-id not found
        echo "ERROR: '$2' is not a valid command or framework-id. Please try again."
        echo "Print framework usage here, etc."
      fi
    elif [[ $# -gt 2 ]]; then
      if [[ $2 == "$(jq -r '.frameworks[] | "\(.id)"' $MESOS_STATE_SUMMARY | grep -i $2)" && $# -ge 3 ]]; then
        if [[ $3 == "agents" ]]; then
          # Print agents for a given framework
          printFrameworkIDAgents
        fi
      fi
    fi
  fi
fi

##################################################
##################################################
##################################################
#####
# Agent
#####
# WIP
printAgentList () {
  echo -e "ID HOSTNAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  jq -r '.slaves[] | "\(.id) \(.hostname)"' $MESOS_STATE_SUMMARY | awk '{ printf "%-80s %-40s\n", $1, $2}'
}

# printAgentResourcesCPU () {
#   TOTAL_CPUS="$(jq '.slaves[] | select(.id == '$2') | .resources.cpus' $MESOS_STATE_SUMMARY)"
#   USED_CPUS="$(jq '.slaves[] | select(.id == '$2') | .used_resources.cpus' $MESOS_STATE_SUMMARY)"
#   FREE_CPUS="$(bc <<< "$TOTAL_CPUS - $USED_CPUS")"
#   UNRESERVED_CPUS="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.cpus' $MESOS_STATE_SUMMARY)"
# }
#
# printAgentResourcesMEM () {
#   TOTAL_MEM="$(jq '.slaves[] | select(.id == '$2') | .resources.mem' $MESOS_STATE_SUMMARY)"
#   USED_MEM="$(jq '.slaves[] | select(.id == '$2') | .used_resources.mem' $MESOS_STATE_SUMMARY)"
#   FREE_MEM="$(bc <<< "$TOTAL_MEM - $USED_MEM")"
#   UNRESERVED_MEM="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.mem' $MESOS_STATE_SUMMARY)"
# }
#
# printAgentResourcesDisk () {
#   TOTAL_DISK="$(jq '.slaves[] | select(.id == '$2') | .resources.disk' $MESOS_STATE_SUMMARY)"
#   USED_DISK="$(jq '.slaves[] | select(.id == '$2') | .used_resources.disk' $MESOS_STATE_SUMMARY)"
#   FREE_DISK="$(bc <<< "$TOTAL_DISK - $USED_DISK")"
#   UNRESERVED_DISK="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.disk' $MESOS_STATE_SUMMARY)"
# }
#
# printAgentResourcesGPUS () {
#   TOTAL_GPUS="$(jq '.slaves[] | select(.id == '$2') | .resources.disk' $MESOS_STATE_SUMMARY)"
#   USED_GPUS="$(jq '.slaves[] | select(.id == '$2') | .used_resources.disk' $MESOS_STATE_SUMMARY)"
#   FREE_GPUS="$(bc <<< "$TOTAL_GPUS - $USED_GPUS")"
#   UNRESERVED_GPUS="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.cpus' $MESOS_STATE_SUMMARY)"
# }

printAgentResources () {
  TOTAL_CPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.cpus' $MESOS_STATE_SUMMARY)"
  TOTAL_MEM="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.mem' $MESOS_STATE_SUMMARY)"
  TOTAL_DISK="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.disk' $MESOS_STATE_SUMMARY)"
  TOTAL_GPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.gpus' $MESOS_STATE_SUMMARY)"

  UNRESERVED_CPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.cpus' $MESOS_STATE_SUMMARY)"
  UNRESERVED_MEM="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.mem' $MESOS_STATE_SUMMARY)"
  UNRESERVED_DISK="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.disk' $MESOS_STATE_SUMMARY)"
  UNRESERVED_GPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.gpus' $MESOS_STATE_SUMMARY)"

  USED_CPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.cpus' $MESOS_STATE_SUMMARY)"
  USED_MEM="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.mem' $MESOS_STATE_SUMMARY)"
  USED_DISK="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.disk' $MESOS_STATE_SUMMARY)"
  USED_GPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.gpus' $MESOS_STATE_SUMMARY)"

  FREE_CPUS="$(bc <<< "$TOTAL_CPUS - $USED_CPUS")"
  FREE_MEM="$(bc <<< "$TOTAL_MEM - $USED_MEM")"
  FREE_DISK="$(bc <<< "$TOTAL_DISK - $USED_DISK")"
  FREE_GPUS="$(bc <<< "$TOTAL_GPUS - $USED_GPUS")"

  echo "┌───────── agent-id: $AGENT_ID "
  echo "├─ CPUS: $TOTAL_CPUS"
  echo "│     ├─ Unreserved: $UNRESERVED_CPUS / $TOTAL_CPUS"
  echo "│     └─ Free: $FREE_CPUS / $TOTAL_CPUS"
  echo "├─ MEM: $TOTAL_MEM"
  echo "│     ├─ Unreserved: $UNRESERVED_MEM / $TOTAL_MEM"
  echo "│     └─ Free: $FREE_MEM / $TOTAL_MEM"
  echo "├─ DISK: $TOTAL_DISK"
  echo "│     ├─ Unreserved: $UNRESERVED_DISK / $TOTAL_DISK"
  echo "│     └─ Free: $FREE_DISK / $TOTAL_DISK"
  echo "├─ GPUS: $TOTAL_GPUS"
  echo "│     ├─ Unreserved: $UNRESERVED_GPUS / $TOTAL_GPUS"
  echo "│     └─ Free: $FREE_GPUS / $TOTAL_GPUS"
  echo "└────────────────────────────────────────────────────────"
}

if [[ $1 == "agent" ]]; then
  # If naked, print usage
  if [[ $# -eq 1 ]]; then
    echo "Print agent usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $# -eq 2 ]]; then
      if [[ $2 == "list" ]]; then
        # Agent list
        printAgentList
      elif [[ $2 == "$(jq -r '.slaves[] | "\(.id)"' $MESOS_STATE_SUMMARY | grep -i $2)" ]]; then
        AGENT_ID=$2
        # Move printAgentResources to dcosjq <agent-id> resources and have naked <agent-id> be an overview of everything agent related.
        printAgentResources
      else
        echo "ERROR: '$2' is not a valid command or agent-id. Please try again."
        echo "Print framework usage here, etc."
      fi
    fi
  fi
fi

##################################################
##################################################
##################################################
#####
# Role
#####
# WIP
printRoleList () {
  echo -e "NAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  jq -r '.roles[] | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_roles.json" | awk '{ printf "%-80s %-40s\n", $1, $2}'
}

printRoleSummary () {
  jq '.roles[] | select(.name == "'$ROLE_NAME'")' $MESOS_LEADER_DIR"/5050-master_roles.json"
}

if [[ $1 == "role" ]]; then
  # If naked, print usage
  if [[ $# -eq 1 ]]; then
    echo "Print role usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $# -eq 2 ]]; then
      if [[ $2 == "list" ]]; then
        # Role list
        printRoleList
      elif [[ $2 == "$(jq -r '.roles[] | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_roles.json" | grep -i $2)" ]]; then
        ROLE_NAME="$2"
        # Print role summary for a given role name
        printRoleSummary
      else
        # Subcommand/framework-id not found
        echo "ERROR: '$2' is not a valid command or role. Please try again."
        echo "Print framework usage here, etc."
      fi
    fi
  fi
fi


#####
# Offer
#####






# echo "nonexit"
# echo "nonexit"
# echo "nonexit"
# echo "nonexit"
# echo "nonexit"



#### fix things
