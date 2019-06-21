## What is dcosjq?
In short, `dcosjq` is a simple command line tool for parsing files contained within [DC/OS diagnostic bundles](https://support.mesosphere.com/s/article/Create-a-DC-OS-Diagnostic-bundle).

The intent of `dcosjq` is to mimic the functionality of the [DC/OS CLI](https://github.com/dcos/dcos-cli) when working with DC/OS diagnostic bundles and parse the information in the bundles more effective and efficiently. To accomplish this, we leverage the use of `jq`. Using `dcosjq` allows you to quickly gather information about a cluster and its state without having to open large, and often cumbersome, JSON files.

This project is currently a work-in-progress and will likely be updated regularly. Any feedback or contributions are welcome.
## Installation
```
$ git clone git@github.com:some-things/dcosjq.git
$ cd dcosjq
$ cp dcosjq.sh /usr/local/bin/dcosjq
$ chmod +x /usr/local/bin/dcosjq
```
## Usage
Note: For JSON and log parsing features, `dcosjq` must be executed from within the DC/OS diagnostic bundles root directory with all files decompressed.
### Parsing JSON files:
#### General Cluster Information:
```
# Relevant DC/OS config.yaml information
$ dcosjq cluster info

# Resources (cpu, mem, disk, gpu) for all agents
$ dcosjq cluster resources
```
#### Exhibitor
```
# Exhibitor/Zookeeper leader
$ dcosjq exhibitor leader

# Exhibitor/Zookeeper status
$ dcosjq exhibitor status
```
#### Mesos
##### - General Information:
```
# Mesos leader
$ dcosjq mesos leader

# Mesos flags
$ dcosjq mesos flags
```
##### - Framework:
```
# Mesos framework list
$ dcosjq framework list

# Mesos framework's information
$ dcosjq framework <id>

# Mesos framework's agents
$ dcosjq framework <id> agents

# Mesos framework's tasks
$ dcosjq framework <id> tasks

# Mesos framework's task's information
$ dcosjq framework <id> tasks <id>

# Mesos framework's roles
$ dcosjq framework <id> roles
```
##### - Task:
```
# Mesos task list
$ dcosjq task list

# Mesos task's information
$ dcosjq task <id>
```
##### - Role:
```
# Mesos role list
$ dcosjq role list

# Mesos role's information
$ dcosjq role <id>

# Mesos role's agents
$ dcosjq role <id> agents
```
##### - Agent:
```
# Mesos agent list
$ dcosjq agent list

# Mesos agent's information
$ dcosjq agent <id>

# Mesos agent's resources (cpu, mem, disk, gpu)
$ dcosjq agent <id> resources

# Mesos agent's frameworks
$ dcosjq agent <id> frameworks

# Mesos agent's tasks
$ dcosjq agent <id> tasks
```
#### Marathon
```
# Marathon leader
$ dcosjq marathon leader

# Marathon information
$ dcosjq marathon info

# Marathon app list
$ dcosjq marathon app list

# Marathon app's JSON configuration
$ dcosjq marathon app <id> show

# Marathon deployment list
$ dcosjq marathon deployment list

# Marathon deployment's information
$ dcosjq marathon deployment <id>

# Marathon group list
$ dcosjq marathon group list

# Marathon group's information
$ dcosjq marathon group <id>

# Marathon pod list
$ dcosjq marathon pod list

# Marathon pod's information
$ dcosjq marathon pod <id> show

# Marathon task list
$ dcosjq marathon task list

# Marathon task's information
$ dcosjq marathon task <id>
```

### Checks:
Note: Checks are to be used as indicators and do not necessarily mean there are any issues within the cluster. In other words, if you are experiencing issues, they may provide helpful information and/or rule out any known/common issues.

```
$ dcosjq checks
```
### Miscellaneous:
Format all JSON files within the current working directory and all sub-directories:

```
$ dcosjq format
```

Extract/decompress/move/format bundle files. Please review and understand the code here before using this feature. All files will be moved to the path specified in `USER_TICKETS_DIR` (Default: $HOME/Documents/logs/tickets) :

```
$ dcosjq extract <bundle-name>.zip
```

## Contributing
Any issues, features, or pull requests are welcome!

## Contact

* Email: dustinmnemes@gmail.com
* GitHub: https://github.com/some-things
* DC/OS Community Slack (https://chat.dcos.io/): @dnemes.mesospshere
