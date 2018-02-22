'''
Ramblings about the PYVMOMI
'''

import ssl,atexit
import argparse
import sys
from os import system, path
import time
import calendar, datetime

from pyVmomi import vim, vmodl
from pyVim import connect
from pyVim.connect import Disconnect, SmartConnect

inputs = {'vcenter_ip': '10.7.20.10',
          'vcenter_password': 'Melody1!',
          'vcenter_user': 'administrator@encore-oam.com',
          'vm_host' : 'r60212c11',
          'vm_name' : 'Test-using-OVFModule',
          'isDHCP' : False,
          'vm_ip' : '10.7.21.157',
          'subnet' : '255.255.255.0',
          'gateway' : '10.7.21.1',
          'dns' : ['11.110.135.51', '11.110.135.52'],
          'iscsi_targets' : ['10.7.21.5', '10.7.22.5'],
          #'ntpservers': [],
          'ntpservers': ['time.nist.gov','pool.ntp.org'],
          'domain' : 'encore-oam.com',
          'ovf_path': '/home/ansible/testovf/test.ovf',
          'custom_spec': {'DeploymentOption': 'ASAV1-10', 'Deployment Type': 'HA'}
          }
          #'ntpservers': ['time.nist.gov','pool.ntp.org'],

def get_ovf_descriptor(ovf_path):
    """
    Read in the OVF descriptor.
    """
    if path.exists(ovf_path):
        with open(ovf_path, 'r') as f:
            try:
                ovfd = f.read()
                f.close()
                return ovfd
            except:
                print "Could not read file: %s" % ovf_path
                exit(1)

def get_obj(content, vimtype, name):
    """
     Get the vsphere object associated with a given text name
    """    
    obj = None
    container = content.viewManager.CreateContainerView(content.rootFolder, vimtype, True)
    for c in container.view:
        if c.name == name:
            obj = c
            break
    return obj

def wait_for_task(task, actionName='job', hideResult=False):
    """
    Waits and provides updates on a vSphere task
    """
    
    while task.info.state == vim.TaskInfo.State.running:
        time.sleep(2)
    
    if task.info.state == vim.TaskInfo.State.success:
        if task.info.result is not None and not hideResult:
            out = '%s completed successfully, result: %s' % (actionName, task.info.result)
            print out
        else:
            out = '%s completed successfully.' % actionName
            print out
    else:
        out = '%s did not complete successfully: %s' % (actionName, task.info.error)
        raise task.info.error
        print out
    
    return task.info.result


def add_ntp_server(host_obj, ntp_servers, policy_state=vim.host.Service.Policy.on, restart_service=False):
    #NTP manager on ESXi host
    dateTimeManager = host_obj.configManager.dateTimeSystem

    # configure NTP Servers if not configured
    #ntpServers = ['192.168.1.100','192.168.1.200']
    if ntp_servers:
        ntpConfig = vim.HostNtpConfig(server=ntp_servers)
        dateConfig = vim.HostDateTimeConfig(ntpConfig=ntpConfig)
        dateTimeManager.UpdateDateTimeConfig(config=dateConfig)

        # start ntpd service
        serviceManager = host_obj.configManager.serviceSystem
        serviceManager.UpdateServicePolicy('ntpd', policy_state)

	#print "Starting ntpd service on " + args.vihost
        if restart_service:
            serviceManager.RestartService(id='ntpd')
        else:
            serviceManager.StartService(id='ntpd')
            
    else:
	print "Error: Unable to start NTP Service because no NTP servers have not been configured"    
 
def iscsi_send_targets(host_obj, send_targets, iscsi_state=True):
    #enable iSCSI 
    host_storage = host_obj.configManager.storageSystem
    
    host_storage.UpdateSoftwareInternetScsiEnabled(iscsi_state)
    host_storage.RescanAllHba()
  
    hba_list = host_storage.storageDeviceInfo.hostBusAdapter
    print hba_list
    #hba_list = host.config.storageDevice.hostBusAdapter
    hba_device = None
    for hba in hba_list:
        if 'iSCSI Software Adapter' in hba.model:
            print hba.device
            hba_device = hba.device
            print hba_device
            print hba.device
            break

    if hba_device:
        #send_target = vim.HostInternetScsiHbaSendTarget(hba_device, send_targets)
        host_storage.AddInternetScsiSendTargets(hba_device, send_targets)
        #else:
        #    print "iSCSI adapter is either not enabled or unavailable at this time."
            #print hba_device
        #sys.exit()
    
    #send_target = vim.HostInternetScsiHbaSendTarget(hba_device, send_targets)
    #host_storage.AddInternetScsiSendTargets(send_target)

def main():
    #args = GetArgs()
    try:
        si = None
        try:
            context = ssl.SSLContext(ssl.PROTOCOL_SSLv23)
            context.verify_mode = ssl.CERT_NONE
            print "Trying to connect to VCENTER SERVER . . ."
            si = connect.Connect(inputs['vcenter_ip'], 443, inputs['vcenter_user'], inputs['vcenter_password'], sslContext=context)
            '''si = connect.SmartConnect(host=args.host,
                                                user=args.user,
                                                pwd=args.password,
                                                port='443',
                                                sslContext=context)'''
            #print "Trying to connect to VCENTER SERVER . . ."
            #si = connect.Connect(inputs['vcenter_ip'], 443, inputs['vcenter_user'], inputs['vcenter_password'])
        except IOError, e:
            pass
            atexit.register(Disconnect, si)

        print "Connected to VCENTER SERVER !"
        
        content = si.RetrieveContent()
        vm_host = inputs['vm_host'] +'.'+ inputs['domain']
        host = get_obj(content, [vim.HostSystem], vm_host)
        if not host:
            print "Unable to locate Physical Host."
        print "=========================================="
        print "host:", host 
        print "=========================================="
        target_lun_uuid = {}
        scsilun_canonical = {}
        scsilun_uuid = {}
        scsilun_devicepath = {}

        storage=host.config.storageDevice
        disk=vim.host.ScsiDisk
        disk=storage.scsiLun
        #print "storage", storage.scsiLun
        #sys.exit()
        disk=vim.host.ScsiDisk        
        #print host.config.storageDevice.scsiLun[0]
        
        # Associate the scsiLun key with the canonicalName (NAA)
        print "Generating SCSI Canonical Array"
        for scsilun in host.config.storageDevice.scsiLun:
            scsilun_canonical[scsilun.key] = scsilun.canonicalName
            scsilun_uuid[scsilun.key] = scsilun.uuid
            #print "SCSI LUN [host.config.storageDevice.scsiLun] is :", scsilun
        print "=========================================="

#        for scsidisk in host.ScsiDisk:
#            #scsilun_devicepath[scsilun.key] = scsidisk.devicePath
#            print scsidisk
#            #print "SCSI DISK [host.config.storageDevice.scsiDisk] is :", scsidisk
#            #print "=========================================="

        print "scsilun_canonical:", scsilun_canonical 
        print "=========================================="
        print "scsilun_uuid:", scsilun_uuid 
        print "=========================================="
        #print "scsilun_devicepath:", scsilun_devicepath 
#        sys.exit()
#
# 
#        scsitop=host.config.storageDevice.scsiTopology
#        print "scsi top is :", scsitop
#        print "=========================================="
#        for adapter in host.config.storageDevice.scsiTopology.adapter:
#            #scsilun_canonical[scsilun.key] = scsilun.canonicalName
#            print "ADAPTER is :", adapter
#
#        print "=========================================="
#	print "ADAPTER[0] is :", host.config.storageDevice.scsiTopology.adapter[0]
#        print "=========================================="
#	print "TARGET of ADAPTER[0] is :", host.config.storageDevice.scsiTopology.adapter[0].target
#        #sys.exit()
#

        # Associate target number with LUN uuid
        print "Generating Target LUN Array"
        for target in host.config.storageDevice.scsiTopology.adapter[2].target:
            for lun in target.lun:
                target_lun_uuid[target.target] = lun.scsiLun
        print "=========================================="
        print "target_lun_uuid is: ", target_lun_uuid 
        print "=========================================="

        for index in range(2,(len(target_lun_uuid)+1)):
            #print index,target_lun_uuid[index]
            #print index,scsilun_canonical[target_lun_uuid[index]]
	    dp = "/vmfs/devices/disks/" + str(scsilun_canonical[target_lun_uuid[index]]) 
	    print "dp is", dp
            if (index < 11):
                datastore_name = inputs['vm_host'] +'-ssd0'+ str((index-1)) 
            else:
                datastore_name = inputs['vm_host'] +'-ssd'+ str((index-1)) 

	    print "datastore name is:", datastore_name
	    #sys.exit()
	    hostdssystem = host.configManager.datastoreSystem
	    dssystem = vim.host.DatastoreSystem
	    diskquery=dssystem.QueryAvailableDisksForVmfs(hostdssystem)
	    #print len(diskquery)
	    #print diskquery[2]
	     
	    vmfs_ds_options = dssystem.QueryVmfsDatastoreCreateOptions(hostdssystem, dp, 5)
	    #print "vmfs_ds_options:", vmfs_ds_options
	    vmfs_ds_options[0].spec.vmfs.volumeName = datastore_name
	    new_ds = dssystem.CreateVmfsDatastore(hostdssystem,vmfs_ds_options[0].spec)
	#sys.exit()   
        
    except vmodl.MethodFault, e:
        print "Caught vmodl fault: %s" % e.msg
        return 1
    except Exception, e:
        print "Caught exception: %s" % str(e)
        return 1
    else:
        print "=========================================="
        print " Datastores are created"
        print "=========================================="

# Start program
if __name__ == "__main__":
    main()
