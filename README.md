# AWS RDP Tunneller

Gets all windows instances for an environment in AWS
Gets the windows password and puts them into KeyChain
Setups ssh tunnel sessions through the public bastion instance
Creates RDP configs and places them into Microsoft Remote Desktop

## Supports

OSX only

## Required

### Gems
```bash
gem install aws-sdk
gem install cfpropertylist
```

## Backup your existing RDP config as this will replace it!
```bash
cp ~/Library/Containers/com.microsoft.rdc.mac/Data/Library/Preferences/com.microsoft.rdc.mac.plist ~/backups/
```
