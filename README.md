# AWS RDP Tunneller

* Gets all windows instances for an environment in AWS
* Gets the windows password and puts them into KeyChain
* Setups ssh tunnel sessions through the public bastion instance
* Creates RDP configs and places them into Microsoft Remote Desktop

## Dependencies

Use bundler to install dependencies within Gemfile

```
bundle install
```

## Usage

```bash
./aws-rdp-tunneller.rb -r us-west-2 -e dev -k devkey.pem
```

### Options
AWS Region (required)
```bash
-r --region us-west-2
```

Environment tag on instances (required)
```bash
-e --environment dev (required)
```

Key used to launch the instance (required)
```bash
-k --private-key devkey.pem
```

SSH user used to connect to the bastion to setup the tunnel. (optional) if defined in your ssh config
```bash
-u --ssh-user ec2-user
```

AWS Profile (optional)
```bash
-p --profile dev
```

Name of bastion host (optional, defaults to "bastion-xx")
```bash
-bm --bastion-name
```

## Supports

OSX only
Microsoft Remote Desktop -v 8.0.18

## Required

### Gems
```bash
gem install aws-sdk
gem install CFPropertyList
```

## Backup your existing RDP config as this will replace it!
```bash
cp ~/Library/Containers/com.microsoft.rdc.mac/Data/Library/Preferences/com.microsoft.rdc.mac.plist ~/backups/
```

## AWS IAM Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1490675007000",
            "Effect": "Allow",
            "Action": [
                "ec2:GetPasswordData",
                "ec2:Describe*"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```
