#!/bin/bash

# RouterOS 6.45.2

# should be uniq in Customer Gateways list
ASN=65000

YOUR_SECRET=

AWS_LAN=x.x.x.x/x
YOUR_LAN1=10.x.x.x/24
YOUR_LAN2=10.x.y.x/24
YOUR_LAN3=10.x.z.x/24

AWS_EXT_IP_ADDR=y.y.y.y
YOUR_EXT_IP_ADDR=z.z.z.z

AWS_INT_Virtual_GW_NET_IP=169.254.x.x
AWS_INT_Virtual_GW_IP=${AWS_INT_Virtual_GW_NET_IP}'+1 for last octet'
YOUR_INT_IP_To_Connect_To_Virtual_GW=${AWS_INT_Virtual_GW_NET_IP}'+2 for last octet'

cat > ./mikrotik.config <<EOF
# add bridge to set obtained routes later
/interface bridge
add arp=disabled name=bridge1-aws-ISP1_vpn1
/ip address
add address=${YOUR_INT_IP_To_Connect_To_Virtual_GW}/30 interface=bridge1-aws-ISP1_vpn1 network=${AWS_INT_Virtual_GW_NET_IP} comment="ipsec AWS" 



# create list with external IPs for ipsec tunnel
/ip firewall address-list
add list=AWS_VPN address=${AWS_EXT_IP_ADDR} \
    comment="AWS Site-to-Site VPN 1st IP addr for ISP1\_ISP (Virtual gw IP). ipsec_aws" 
add list=AWS_VPN address=${AWS_INT_Virtual_GW_NET_IP}/30 \
    comment="AWS Site-to-Site VPN 1st internal IP addr of Net for ISP1 IPS (Virtual gw IP). ipsec_aws"



# create list with AWS lans
add list=AWS_Sends address=${AWS_LAN} \
    comment="AWS Net to obtain with BGP from AWS VPC. ipsec_aws"



# create list with local lans
add list=AWS_Gets address=${YOUR_LAN1} \
    comment="Our Net to announce with BGP to AWS VPC. ipsec_aws"
add list=AWS_Get address=${YOUR_LAN2} \
    comment="Our Net to announce with BGP to AWS VPC. ipsec_aws"
add list=AWS_Gets address=${YOUR_LAN3} \
    comment="Our Net to announce with BGP to AWS VPC. ipsec_aws"



# set ipsec tunnel params
/ip ipsec policy group
add name=AWS

/ip ipsec proposal
set [ find default=yes ] disabled=yes
add enc-algorithms=aes-128-cbc lifetime=1h name=aws-ipsec-vpn-via-ISP1_1

/ip ipsec profile
set [ find default=yes ] dh-group=modp1024 dpd-interval=10s dpd-maximum-failures=3 enc-algorithm=aes-128 lifetime=8h name=AWS nat-traversal=no

/ip ipsec peer
add address=${AWS_EXT_IP_ADDR}/32 local-address=${YOUR_EXT_IP_ADDR} name=peer1-aws-ISP1 comment="ISP1 vpn1. ipsec_aws" 

/ip ipsec identity
add generate-policy=port-override notrack-chain=prerouting peer=peer1-aws-ISP1 policy-template-group=AWS secret=${YOUR_SECRET} comment="ipsec_aws"

/ip ipsec policy
set 0 disabled=yes
add dst-address=${AWS_INT_Virtual_GW_IP}/32 peer=peer1-aws-ISP1 proposal=aws-ipsec-vpn-via-ISP1_1 sa-dst-address=${AWS_EXT_IP_ADDR} sa-src-address=${YOUR_EXT_IP_ADDR} src-address=${YOUR_INT_IP_To_Connect_To_Virtual_GW}/32 tunnel=yes comment="ISP1_vpn2. ipsec_aws" 
add dst-address=${AWS_LAN} peer=peer1-aws-ISP1 proposal=aws-ipsec-vpn-via-ISP1_1 sa-dst-address=${AWS_EXT_IP_ADDR} sa-src-address=${YOUR_EXT_IP_ADDR} src-address=${YOUR_LAN1} tunnel=yes comment="ISP1_vpn1. ipsec_aws" 	
add dst-address=${AWS_LAN} peer=peer1-aws-ISP1 proposal=aws-ipsec-vpn-via-ISP1_1 sa-dst-address=${AWS_EXT_IP_ADDR} sa-src-address=${YOUR_EXT_IP_ADDR} src-address=${YOUR_LAN2} tunnel=yes comment="ISP1_vpn1. ipsec_aws" 	
add dst-address=${AWS_LAN} peer=peer1-aws-ISP1 proposal=aws-ipsec-vpn-via-ISP1_1 sa-dst-address=${AWS_EXT_IP_ADDR} sa-src-address=${YOUR_EXT_IP_ADDR} src-address=${YOUR_LAN3} tunnel=yes comment="ISP1_vpn1. ipsec_aws"

# set BGP
/routing bgp instance
set [find default=yes] disabled=yes
add as=${ASN} name=bgp1-aws-vpn1-ISP1 router-id=${YOUR_INT_IP_To_Connect_To_Virtual_GW} disabled=yes comment="local BGP (Int. Customer gw IP). ipsec_aws"

/routing bgp network
add network=${YOUR_LAN1} comment="announce to AWS VPC. ipsec_aws"
add network=${YOUR_LAN2} comment="announce to AWS VPC. ipsec_aws"
add network=${YOUR_LAN3} comment="announce to AWS VPC. ipsec_aws"

/routing bgp peer
add hold-time=30s instance=bgp1-aws-vpn1-ISP1 keepalive-time=10s name=AWS-peer1-ISP1 remote-address=${AWS_INT_Virtual_GW_IP} ttl=default update-source=bridge1-aws-ISP1_vpn1 comment="AWS Internal IP of Virtual GW. ipsec_aws"



# allow tunnel and forwards for nets
/ip firewall filter
add action=accept chain=input dst-address-list=AWS_VPN src-address-list=AWS_VPN comment="to establish tunnels. ipsec_aws"
add action=fasttrack-connection chain=forward connection-state=established,related dst-address-list=AWS_Gets protocol=tcp src-address-list=AWS_Sends comment="ipsec_aws"
add action=fasttrack-connection chain=forward connection-state=established,related dst-address-list=AWS_Gets protocol=udp src-address-list=AWS_Sends comment="ipsec_aws"
add action=fasttrack-connection chain=forward connection-state=established,related dst-address-list=AWS_Sends protocol=tcp src-address-list=AWS_Gets comment="ipsec_aws"
add action=fasttrack-connection chain=forward connection-state=established,related dst-address-list=AWS_Sends protocol=udp src-address-list=AWS_Gets comment="ipsec_aws"
add action=accept chain=forward connection-state=new dst-address-list=AWS_Gets src-address-list=AWS_Sends comment="ipsec_aws"
add action=accept chain=forward connection-state=new dst-address-list=AWS_Sends src-address-list=AWS_Gets comment="ipsec_aws"



# just for /ip firewall connection
/ip firewall mangle
add action=mark-connection chain=prerouting connection-mark=no-mark dst-address-list=AWS_Gets new-connection-mark=IPSec_IN passthrough=yes src-address-list=AWS_Sends comment="ipsec_aws"
add action=mark-connection chain=prerouting connection-mark=no-mark dst-address-list=AWS_Sends new-connection-mark=IPSec_OUT passthrough=yes src-address-list=AWS_Gets comment="ipsec_aws"
add action=mark-connection chain=prerouting connection-mark=no-mark dst-address-list=AWS_VPN new-connection-mark=IPSec_tunnel passthrough=yes src-address-list=AWS_VPN comment="ipsec_aws"

EOF
