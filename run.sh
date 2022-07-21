#!/bin/bash

players=("dashjs" "hlsjs")
id=$(date '+%s')
awsProfile="default"
placementGroup="pptCluster"
awsKey=""
awsIAMRole="SSMEnabled"
awsSecurityGroup="ppt-security-group"
serverInstanceId=""
clientInstanceIds=""
networkConfig=""
clientInstancesType="m5ad.2xlarge"
serverInstancesType="m5ad.24xlarge"
instanceRegion="eu-central-1"
instanceAvailabilityZone="eu-central-1b"
clientWarmupTime=1 #s

showError() {
  now=$(date -u +"%H:%M:%S")
  printf "\e[1;31m>>> [ERROR %s] %s\e[0m\n" "$now" "$1"
  cleanExit 1
}

showMessage() {
  now=$(date -u +"%H:%M:%S")
  printf "\n\e[1;36m>>> [INFO %s] %s\e[0m\n" "$now" "$1"
}

cleanExit() {
  showMessage "Killing EC2 instances and clean ups"
  aws ec2 terminate-instances --instance-ids $clientInstanceIds $serverInstanceId --profile $awsProfile &>/dev/null
  rm -rf "$id"
  exit $1
}

argumentIndex=0
for argument in "$@"; do
  if [[ $argument == *"--"* ]]; then
    case $argument in
    "--shaper")
      nextArgumentIndex=$((argumentIndex + 2))
      networkConfigFileName="${!nextArgumentIndex}"
      networkConfig=$(cat $networkConfigFileName) || showError "Could not load the network config file"
      shaperDurations=($(echo "$networkConfig" | jq '.[].duration'))
      serverIngresses=($(echo "$networkConfig" | jq '.[].serverIngress'))
      serverEgresses=($(echo "$networkConfig" | jq '.[].serverEgress'))
      serverLatencies=($(echo "$networkConfig" | jq '.[].serverLatency'))
      clientIngresses=($(echo "$networkConfig" | jq '.[].clientIngress'))
      clientEgresses=($(echo "$networkConfig" | jq '.[].clientEgress'))
      clientLatencies=($(echo "$networkConfig" | jq '.[].clientLatency'))
      ;;
    "--cluster")
      nextArgumentIndex=$((argumentIndex + 2))
      placementGroup="${!nextArgumentIndex}"
      ;;
    "--awsProfile")
      nextArgumentIndex=$((argumentIndex + 2))
      awsProfile="${!nextArgumentIndex}"
      ;;
    "--awsKey")
      nextArgumentIndex=$((argumentIndex + 2))
      awsKey="${!nextArgumentIndex}"
      ;;
    "--awsIAMRole")
      nextArgumentIndex=$((argumentIndex + 2))
      awsIAMRole="${!nextArgumentIndex}"
      ;;
    "--awsSecurityGroup")
      nextArgumentIndex=$((argumentIndex + 2))
      awsSecurityGroup="${!nextArgumentIndex}"
      ;;
    "--players")
      valueIndex=0
      newPlayers=()
      for value in "$@"; do
        if [[ $valueIndex -gt $argumentIndex ]]; then
          if [[ $value == *"--"* ]]; then
            break
          fi
          playerQuantity="$(cut -d 'x' -f 1 <<<"$value")"
          playerName="$(cut -d 'x' -f 2- <<<"$value")"
          if [[ " ${players[@]} " =~ " ${playerName} " ]]; then
            until [ $playerQuantity -lt 1 ]; do
              newPlayers+=($playerName)
              let playerQuantity-=1
            done
          else
            showError "Invalid player '$value'"
          fi
        fi
        ((valueIndex++))
      done
      if [[ ${#newPlayers[@]} -lt 1 ]]; then
        showError "Define at least one player"
      fi
      players=(${newPlayers[@]})
      ;;
    *)
      showError "Invalid argument '$argument'"
      ;;
    esac
  fi
  ((argumentIndex++))
done

printf "\n\e[1;33m>>> Experiment set id: $id %s\e[0m\n"
mkdir "$id"

durationOfExperiment=0
for duration in "${shaperDurations[@]}"; do
  durationOfExperiment=$(echo "$durationOfExperiment + $duration" | bc -l)
done

showMessage "Running experiment on the following players for ${durationOfExperiment}s each"
printf '%s ' "${players[@]}"
printf "\n"

showMessage "Spinning up server EC2 instance"
aws ec2 run-instances \
  --region $instanceRegion \
  --image-id ami-0ab838eeee7f316eb \
  --instance-type $serverInstancesType \
  --key-name $awsKey \
  --placement "GroupName=$placementGroup,AvailabilityZone=$instanceAvailabilityZone" \
  --iam-instance-profile Name=$awsIAMRole \
  --security-groups $awsSecurityGroup \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=lll-cadvise-server-$id}]" \
  --profile $awsProfile >"$id/instance.json" || showError "Failed to run the aws command. Check your aws credentials."

serverInstanceId=$(jq -r '.Instances[].InstanceId' <"$id/instance.json")
printf '%s ' "${serverInstanceId[@]}"
printf "\n"

showMessage "Spinning up client EC2 instance(s)"
aws ec2 run-instances \
  --region $instanceRegion \
  --image-id ami-0ab838eeee7f316eb \
  --count ${#players[@]} \
  --instance-type $clientInstancesType \
  --key-name $awsKey \
  --placement "GroupName=$placementGroup,AvailabilityZone=$instanceAvailabilityZone" \
  --iam-instance-profile Name=$awsIAMRole \
  --security-groups $awsSecurityGroup \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=lll-cadvise-client-$id}]" \
  --profile $awsProfile >"$id/instances.json" || showError "Failed to run the aws command. Check your aws credentials."

clientInstanceIds=$(jq -r '.Instances[].InstanceId' <"$id/instances.json")
printf '%s ' "${clientInstanceIds[@]}"
printf "\n"

showMessage "Waiting for instances to be in running state"
stateCodes=0
while [ $stateCodes == 0 ] || [ $(($stateCodesSum / ${#stateCodes[@]})) != 16 ]; do
  stateCodesSum=0
  sleep 3
  stateCodes=($(aws ec2 describe-instances --instance-ids $clientInstanceIds $serverInstanceId --profile $awsProfile | jq '.Reservations[].Instances[].State.Code'))
  for stateCode in "${stateCodes[@]}"; do
    ((stateCodesSum += stateCode))
  done
done
echo "all up [$stateCodesSum]"

clientPublicIps=($(aws ec2 describe-instances --instance-ids $clientInstanceIds --profile $awsProfile | jq -r '.Reservations[].Instances[].PublicIpAddress'))
serverPublicIp=($(aws ec2 describe-instances --instance-ids $serverInstanceId --profile $awsProfile | jq -r '.Reservations[].Instances[].PublicIpAddress'))
serverPrivateIp=$(jq -r '.Instances[].PrivateIpAddress' <"$id/instance.json")
configSkeleton=$(cat configSkeleton.json)

((durationOfExperiment += clientWarmupTime)) # warm up client
config="${configSkeleton/--id--/$id}"
config="${config/--serverIp--/$serverPrivateIp}"
config="${config/--experimentDuration--/$durationOfExperiment}"

shaperIndex=0
networkConfig="{
    \"duration\": ${clientWarmupTime},
    \"serverIngress\": 0,
    \"serverEgress\": 0,
    \"serverLatency\": 0,
    \"clientIngress\": 0,
    \"clientEgress\": 0,
    \"clientLatency\": 0
  }"
while [ $shaperIndex -lt "${#shaperDurations[@]}" ]; do
  if [[ $networkConfig != "" ]]; then
    networkConfig+=","
  fi
  networkConfig+="{
    \"duration\": ${shaperDurations[shaperIndex]},
    \"serverIngress\": ${serverIngresses[shaperIndex]},
    \"serverEgress\": ${serverEgresses[shaperIndex]},
    \"serverLatency\": ${serverLatencies[shaperIndex]},
    \"clientIngress\": ${clientIngresses[shaperIndex]},
    \"clientEgress\": ${clientEgresses[shaperIndex]},
    \"clientLatency\": ${clientLatencies[shaperIndex]}
  }"
  ((shaperIndex++))
done
networkConfig="[${networkConfig}]"
config="${config/\"--shapes--\"/$networkConfig}"

playerIndex=0
for publicIp in "${clientPublicIps[@]}"; do
  if [[ $playerIndex == 0 ]]; then
    config="${config/--player--/${players[playerIndex]}}"
    config="${config/--playerIndex--/p$playerIndex}"
  else
    previousIndex=$((playerIndex - 1))
    config="${config/${players[previousIndex]}/${players[playerIndex]}}"
    config="${config/p$previousIndex/p$playerIndex}"
  fi
  echo "$config" >"$id/config.json"

  showMessage "Waiting for client network interface to be reachable [${players[playerIndex]}]"
  while ! nc -w5 -z "$publicIp" 22; do
    sleep 1
  done

  showMessage "Injecting scripts and configurations into client instance"
  scp -oStrictHostKeyChecking=no -i "./$awsKey.pem" client/init.sh client/start.sh "$id/config.json" ec2-user@"$publicIp":/home/ec2-user

  ((playerIndex++))
done

showMessage "Waiting for server network interface to be reachable"
while ! nc -w5 -z "$serverPublicIp" 22; do
  sleep 1
done

showMessage "Injecting scripts and configurations into server instance"
scp -oStrictHostKeyChecking=no -i "./$awsKey.pem" server/init.sh server/start.sh server/server.js server/package.json server/FreeSans.ttf server/eval.js "$id/config.json" ec2-user@"$serverPublicIp":/home/ec2-user

showMessage "Executing initializer script(s)"
SSMCommandId=$(aws ssm send-command \
  --targets "Key=tag:Name,Values=lll-cadvise-server-$id,lll-cadvise-client-$id" \
  --document-name "AWS-RunShellScript" \
  --comment "Initialize" \
  --parameters commands="/home/ec2-user/init.sh" \
  --output-s3-bucket-name "ppt-output" \
  --output-s3-key-prefix "init-out/$id" \
  --query "Command.CommandId" \
  --profile $awsProfile | sed -e 's/^"//' -e 's/"$//')

echo "$SSMCommandId"

SSMCommandResult="InProgress"
timer=0
while [[ $SSMCommandResult == *"InProgress"* ]]; do
  minutes=$((timer / 60))
  seconds=$((timer % 60))
  printf '\r%s' "~ $minutes:$seconds  "
  if [ $((timer % 5)) == 0 ]; then
    SSMCommandResult=$(aws ssm list-command-invocations --command-id $SSMCommandId --profile $awsProfile | jq -r '.CommandInvocations[].Status')
    sleep 0.4
  else
    sleep 1
  fi
  ((timer += 1))
done
printf "\n"

if [[ $SSMCommandResult == *"Failed"* ]]; then
  showError "Failed to initiate the instance(s). Check the S3 bucket for details"
fi

showMessage "Running experiment [+$clientWarmupTime(s) Client warmup time]"
SSMCommandId=$(aws ssm send-command \
  --targets "Key=tag:Name,Values=lll-cadvise-server-$id,lll-cadvise-client-$id" \
  --document-name "AWS-RunShellScript" \
  --comment "Start" \
  --parameters commands="/home/ec2-user/start.sh" \
  --output-s3-bucket-name "ppt-output" \
  --output-s3-key-prefix "start-out/$id" \
  --query "Command.CommandId" \
  --profile $awsProfile | sed -e 's/^"//' -e 's/"$//')

echo "$SSMCommandId"

SSMCommandResult="InProgress"
time=$durationOfExperiment
timer=$time
while [[ $SSMCommandResult == *"InProgress"* ]]; do
  minutes=$((timer / 60))
  seconds=$((timer % 60))
  printf '\r%s' "~ $minutes:$seconds  "
  if [ $((timer % 30)) == 0 ] || [[ $((time - timer)) -gt $time ]]; then
    SSMCommandResult=$(aws ssm list-command-invocations --command-id $SSMCommandId --profile $awsProfile | jq -r '.CommandInvocations[].Status')
    sleep 0.4
  else
    sleep 1
  fi
  ((timer -= 1))
done
printf "\n"

if [[ $SSMCommandResult == *"Failed"* ]]; then
  showError "Failed to run experiment(s). Check the S3 bucket for details"
fi

cleanExit 0
