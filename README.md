# Cisco AnyConnect Dynamic ACL Bypass

Dynamically update access control lists on Cisco ASA (and maybe FTD)

Intended to become the source of truth for managing AnyConnect split tunnel network policy.

## ASA Pre-Req

This routine anticipates the named ACL be manually defined within the ASA running config.
it needs to be created with a remark statement line for the program to confirm processing the list.

```code
access-list exclude-vpn line 1 remark **do NOT modify - anyconnect split-tunnel bypasses**
```

Once created, bind the named-ACL with your groups policies.

```code
group-policy YourRemoteAccessPolicy attributes
 split-tunnel-policy excludespecified
  ipv6-split-tunnel-policy excludespecified
  split-tunnel-network-list value exclude-vpn
```

## Configuration

Create your local [inc/config.tcl](inc/config.tcl.example)

## Input lists

[exclude.txt](lists/exclude.txt.example) will filter networks from your dynamic inputs. The CIDR's must match exactly how they appeared in the source feed to exclude them from the final acl config.

[static.txt](lists/static.txt.example) contains your traditional static CIDR entries which would normally be manually included in the final acl.

[dynamic.txt](lists/dynamic.txt.example) needs to be populated by an external process to fetch the Office365, WebEx, Zoom, etc feeds.


### Example

Generate dynamic.txt using [nabbi/dynamic-allow-lists](https://github.com/nabbi/dynamic-allow-lists)

```shell
LISTSPATH=/opt/dynamic-allow-lists
rm ./lists/dynamic.txt
${LISTSPATH}/cisco-webex.tcl >> ./lists/dynamic.txt
${LISTSPATH}/zoom.tcl >> ./lists/dynamic.txt
${LISTSPATH}/microsoft-office365.tcl >> ./lists/dynamic.txt
```

Run the dynamic acl automation

```shell
./anyconnect-dynamic-acl.tcl
```

