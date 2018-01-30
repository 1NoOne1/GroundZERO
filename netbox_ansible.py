# -*- coding: utf-8 -*-

# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import absolute_import, division, print_function
__metaclass__ = type


import io
import os
import sys
import time
import traceback
import requests, urllib, json


from ansible.module_utils._text import to_text, to_native
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.six import string_types
from ansible.module_utils.urls import open_url

#class RequestError(Exception):
#    """Basic Request Exception
#    More detailed exception that returns the requests object. Along
#    with some attributes with specific details from the requests
#    object.
#    """
#    def __init__(self, message):
#        req = message
#        message = "The request failed with code {} {}".format(
#            req.status_code,
#            req.reason
#        )
#        super(RequestError, self).__init__(message)
#        self.req = req
#        self.request_body = req.request.body
#        self.url = req.url
#        self.error = req.text
#
class NetboxAPI(object):

    def __init__(self, module, url, token):
        self.module = module
        self.url = url + '/api/'
        self.token = token
        self.headers = {
            'Authorization': 'Token ' + self.token,
#            'Accept': 'application/json; indent=4',
            'Content-Type': "application/json"
        }

    def filter(self, endpoint, query = {}):
        full_url = self.url + endpoint + '/?' + urllib.urlencode(query)
        req = requests.get(full_url, headers=self.headers)
        if req.ok:
            return json.loads(req.text)
        else:
            raise Exception(req.text)

    def get_all(self, endpoint):
        return self.filter(endpoint)

    def get(self, endpoint, query = {}):
        req =self.filter(endpoint, query = query)
        data = req['results']
        if len(data) == 1:
            return data[0]
        if len(data) == 0:
            return None
        else:
            raise ValueError('get() returned more than one result.')
    def put(self, endpoint, id, data):
        full_url = self.url + endpoint + '/' + str(id)
        req = requests.put(full_url, headers=self.headers, data=json.dumps(data))
        if req.ok:
            return json.loads(req.text)
        else:
            raise Exception(req.text)

    def patch(self, endpoint, id, data):
        full_url = self.url + endpoint + '/' + str(id)
        req = requests.patch(full_url, headers=self.headers, data=json.dumps(data))
        if req.ok:
            return req.json()
        else:
            raise Exception(req.text)

    def post(self, endpoint, data):
        full_url = self.url + endpoint + '/'
	req = requests.post(
	    full_url,
	    headers=self.headers,
	    data=json.dumps(data)
	)
        try:
            req.raise_for_status()
        except requests.exceptions.HTTPError:
            e = requests.exceptions.HTTPError
            return e.message
        return req.json()

#        if req.ok:
#            return req.json()
            #return json.loads(req.text)
#        else:
            #self.module.fail_json(msg="issue is....%s" %(json.loads(req)))
#            raise Exception(req.json())
#            message = "The request failed with code {} {} {}".format(
#               req.status_code,
#               req.reason,
#               req.text
#            )
#            raise Exception(message) 

    def delete(self, endpoint, id):
        full_url = self.url + endpoint + '/' + str(id)
        req = requests.delete(
            full_url,
            headers=self.headers,
        )
        if req.ok:
            return True
        else:
            raise Exception(req.text)

#    def create_vm(self, vm_endpoint, cluster_endpoint, vm, cluster):
#        vm_id = None
#        #get_vm = self.get(vm_endpoint, {'name':vm})
#        try:
#            get_cluster = self.get(cluster_endpoint, {'name':cluster})
#        except Exception,e:
#            self.module.fail_json(msg=".........%s" %(e.message))
#        
#        post_vm = self.post(vm_endpoint, {'name':vm,'cluster':get_cluster['id']})
#        #try:
#        #    post_vm = self.post(vm_endpoint, {'name':vm,'cluster':get_cluster['id']})
#        #except Exception,e:
#        #    self.module.fail_json(msg="%s" %(e.message))
#
#	vm_id = post_vm['id']
#	return vm_id


    def create_vm(self, vm_endpoint, cluster_endpoint, vm, cluster):
	vm_id = None
	get_vm = self.get(vm_endpoint, {'name':vm})
	get_cluster = self.get(cluster_endpoint, {'name':cluster})
	if get_cluster is None:
	    self.module.fail_json(msg="The given cluster : [%s] doesn't exist in NetBox. Please create it in NetBox." % cluster)
	else:
	    if get_vm != None:
                
                #self.module.exit_json(changed=False, instance=get_vm)
	        self.module.fail_json(changed=False, instance=get_vm, msg="An existing VM : [%s] found in the NetBox. Either use different Name or Delete the esxisting VM"
                                           "and it's entities from the Netbox and then try again." % vm)
	    else:
		post_vm = self.post(vm_endpoint, {'name':vm, 'cluster':get_cluster['id']})
		vm_id = post_vm['id']
	    return vm_id

    def create_ipaddress(self, ipaddress_endpoint, ip_data):
        ip_id = None
        post_ipaddr = self.post(ipaddress_endpoint, ip_data)
        ip_id = post_ipaddr['id']
        return ip_id

    def create_interface(self, vm_inteface_endpoint, interface_data_list):
        interface_ids = []
        for interface_data in interface_data_list:
            post_interface = self.post(vm_inteface_endpoint, interface_data)
            interface_ids.append(post_interface['id'])
        return interface_ids

    def delete_vm(self, vm_endpoint, vm_id):
        self.delete(vm_endpoint, vm_id)

    #def delete_ip(ip_id):
    #    netbox_api_obj.delete(ipaddress_endpoint, ip_id)

    def cleanup_on_error(self, vm_endpoint, vm_id):
        if vm_id:
            self.delete_vm(vm_endpoint, vm_id)
    #    if ip_id:
    #        delete_ip(ip_id)



def main():
    module = AnsibleModule(
        argument_spec=dict(
        netbox_url=dict(type='str', required=True),
        netbox_apitoken=dict(type='str', required=True),
        vm_name=dict(type='str', required=True),
        cluster_name=dict(type='str', required=True),
        ip_addresses=dict(type='list', default=[])
        )
    )

    nb_url = module.params['netbox_url']
    nb_token = module.params['netbox_apitoken']
    vm = module.params['vm_name']
    cluster = module.params['cluster_name']
    ip_addr = module.params['ip_addresses'] 
    
#    module.fail_json(msg="interface datta is : [%s] " % ip_addr)
#    for i,ipx in enumerate(ip_addr):
#        interface = 'eth'+str(i)
#        module.fail_json(msg="interface datta is : [%s] " % interface)
    #netbox_url = 'http://10.7.20.88:8000'
    #token = 'a6d9a8e71a1c7cfc96475f1c2baac23d55841ed8'

    vm_endpoint = 'virtualization/virtual-machines'
    cluster_endpoint = 'virtualization/clusters'
    vm_inteface_endpoint = 'virtualization/interfaces'
    ipaddress_endpoint = 'ipam/ip-addresses'
    vrf_endpoint = 'ipam/vrfs'

    netbox_api_obj = NetboxAPI(module, nb_url, nb_token)

    vm_id = None
    interface_ids = []
    ip_ids = []
    try:
        vm_id = netbox_api_obj.create_vm(vm_endpoint, cluster_endpoint, vm, cluster)
	if vm_id:
	    interface_data = []
	    for idx, ip in enumerate(ip_addr):
		interface = {'virtual_machine':vm_id, 'name':'eth'+str(idx)}
		interface_data.append(interface)
	    interface_ids = netbox_api_obj.create_interface(vm_inteface_endpoint, interface_data)
	    for idx, ip in enumerate(ip_addr):
		get_vrf = netbox_api_obj.get(vrf_endpoint, {'name':ip['vrf']})
		if get_vrf is None:
                    netbox_api_obj.cleanup_on_error(vm_endpoint, vm_id)
		    module.fail_json(msg="The given VRF : [%s] doesn't exist in NetBox. Please create it in NetBox." % ip['vrf'])
		else:
		    ip_id = netbox_api_obj.create_ipaddress(ipaddress_endpoint, {'address':ip['ip'], 'vrf':get_vrf['id'], 'interface':interface_ids[idx]})
		    ip_ids.append(ip_id)
            changed = True
            vm_results =  netbox_api_obj.get(vm_endpoint, {'name':vm}) 
            module.exit_json(changed=vm_results)
            #return changed
	    #if ip_id:
		#    create_interface({'virtual_machine':'vm_obj.id','name':'eth0'}) # need to pass data
    #module.exit_json(msg="something is %s" %vm_id)
    except Exception, e:
        netbox_api_obj.cleanup_on_error(vm_endpoint, vm_id)
        module.fail_json(msg=str(e))
        #result_changed = False
        #return result_changed

    #if result_changed is not None:
    #    vm_results =  netbox_api_obj.get(vm_endpoint, {'name':vm}) 
    #    module.exit_json(msg="....%s" %(vm_results))

if __name__ == '__main__':
    main()

#        if vm_id:
#            interface_data = []
#            for idx, val in enumerate(input['ipaddresses']):
#                interface = {'virtual_machine':vm_id,'name':'eth'+str(idx)}
#                interface_data.append(interface)
#
#            interface_ids = create_interface(interface_data) # need to pass data
#
#            for idx, val in enumerate(input['ipaddresses']):
#               vrf_dict = netbox_api_obj.get(vrf_endpoint, {'name':val['vrf']})
#               print "vrf_dict is :%s" % vrf_dict['id']
#               #ip_id = create_ipaddress({'address':val['ip'], 'vrf':val['vrf'], 'interface_id':interface_ids[idx]}) # need to pass data
#               if vrf_dict is None:
#                   raise Exception("The given VRF : %s doesn't exist in netbox. Please create it first." % val['vrf'])
#               else:
#                   ip_id = create_ipaddress({'address':val['ip'], 'vrf':vrf_dict['id'], 'interface':interface_ids[idx]})
#                   #ip_id = create_ipaddress({'address':val['ip'], 'vrf_id':vrf_dict['id'], 'vrf':vrf_dict['name'], 'interface':interface_ids[idx]})
#                   ip_ids.append(ip_id)
#            #if ip_id:
#            #    create_interface({'virtual_machine':'vm_obj.id','name':'eth0'}) # need to pass data
#    except Exception, e:
#        print str(e.message)
#        cleanup_on_error(vm_id, ip_id=None)
#
#
#    def create_vm(vm_data):
#	vm_id = None
#    	vm_dict = netbox_api_obj.get(vm_endpoint, {'name':vm_data['name']})
#	print vm_data['cluster']
#	cluster_dict = netbox_api_obj.get(cluster_endpoint, {'name':vm_data['cluster']})
#	print "vm_dict:%s" % vm_dict
#	if cluster_dict is None:
#	    raise Exception("The given cluster : %s doesn't exist in netbox. Please create it first." % vm_data['cluster'])
#	else:
#	    if vm_dict != None:
#		raise Exception("VM already exists")
#	    else:
#		print 'test....'
#		result = netbox_api_obj.post(vm_endpoint, {'name':vm_data['name'],'cluster':cluster_dict['id']})
#		print result,'-------------------', result.keys()
#		vm_id = result['id']
#		print vm_id,'id internal.......'
#	    return vm_id
#
#    def create_ipaddress(ip_data):
#	ip_id = None
#	#ip_dict = netbox_api_obj.get(ipaddress_endpoint, {'address':ip_data['address'], 'vrf_id':ip_data['vrf']})
#	#print '>>>>>>>>>>>',ip_dict,'<<<<<<<<<'
#	#if ip_dict != None:
#	#    raise Exception("IP address already exists")
#	#else:
#	result = netbox_api_obj.post(ipaddress_endpoint, ip_data)
#	ip_id = result['id']
#	return ip_id
#
#    def create_interface(interface_data_list):
#	interface_ids = []
#	for interface_data in interface_data_list:
#	    result = netbox_api_obj.post(vm_intefaces_endpoint, interface_data)
#	    interface_ids.append(result['id'])
#	return interface_ids
#
#    def delete_vm(vm_id):
#	netbox_api_obj.delete(vm_endpoint, vm_id)
#
#    #def delete_ip(ip_id):
#    #    netbox_api_obj.delete(ipaddress_endpoint, ip_id)
#
#    def cleanup_on_error(vm_id, ip_id=None):
#	if vm_id:
#	    delete_vm(vm_id)
#    #    if ip_id:
#    #        delete_ip(ip_id)
#
#if __name__ == "__main__":
#    main()
#    input = {
#      'vmname': 'vm_test_name1',
#      'cluster': 'az1',
#      'ipaddresses': [
#              {'vrf': 'Encore', 'ip': '7.7.7.7/24'},
#              {'vrf': 'Encore', 'ip': '8.8.8.8/24'},
#              {'vrf': 'Encore', 'ip': '10.10.10.10/24'}
#      ]
#    }
#    vm_id = None
#    interface_ids = []
#    ip_ids = []
#    #ips_list = ['','']
#    try:
#        vm_data = {'name': input['vmname'],'cluster': input['cluster']}
#        vm_id = create_vm(vm_data) # need to pass data
#        if vm_id:
#            interface_data = []
#            for idx, val in enumerate(input['ipaddresses']):
#                interface = {'virtual_machine':vm_id,'name':'eth'+str(idx)}
#                interface_data.append(interface)
#
#            interface_ids = create_interface(interface_data) # need to pass data
#
#            for idx, val in enumerate(input['ipaddresses']):
#               vrf_dict = netbox_api_obj.get(vrf_endpoint, {'name':val['vrf']})
#               print "vrf_dict is :%s" % vrf_dict['id']
#               #ip_id = create_ipaddress({'address':val['ip'], 'vrf':val['vrf'], 'interface_id':interface_ids[idx]}) # need to pass data
#               if vrf_dict is None:
#                   raise Exception("The given VRF : %s doesn't exist in netbox. Please create it first." % val['vrf'])
#               else:
#                   ip_id = create_ipaddress({'address':val['ip'], 'vrf':vrf_dict['id'], 'interface':interface_ids[idx]})
#                   #ip_id = create_ipaddress({'address':val['ip'], 'vrf_id':vrf_dict['id'], 'vrf':vrf_dict['name'], 'interface':interface_ids[idx]})
#                   ip_ids.append(ip_id)
#            #if ip_id:
#            #    create_interface({'virtual_machine':'vm_obj.id','name':'eth0'}) # need to pass data
#    except Exception, e:
#        print str(e.message)
#        cleanup_on_error(vm_id, ip_id=None)
#
#quit()
#
#
#    if not HAS_PYVMOMI:
#        module.fail_json(msg='pyvmomi python library not found')
#
#    pyv_ovf = PyVmomi(module)
#    pyv_vmomihelper = PyVmomiHelper(module)
#    vm_ovf = pyv_ovf.get_vm()
#
#    #vm_find = find_vm_by_name()
#    #vm_ovf_helper = pyv_vmomihelper.get_vm()
#
#    deploy_ovf = VMwareDeployOvf(module)
#    deploy_ovf_PyVmH = PyVmomiHelper(module)
#
#    vm = deploy_ovf.get_vm_obj()
#
#    if vm:
#        if vm.runtime.powerState != 'poweredOff':
#            if module.params['force']:
#                 set_vm_power_state(deploy_ovf_PyVmH.content, vm, 'poweredoff', module.params['force'])
#            else:
#                 module.fail_json(msg="Virtual Machine is Powered ON. Please Power Off the VM or use force to power it off before doing any customizations.")
#        if module.params['networks'] or module.params['customization']:
#            deploy_ovf_PyVmH.customize_vm(vm)
#            myspec=deploy_ovf_PyVmH.customspec
#            task=vm.CustomizeVM_Task(spec=myspec)
# 
#            facts = deploy_ovf.vm_power_on(vm)
#  
#            #wait_for_task(task)
#            #task_power=vm.PowerOn()
#            #wait_for_task(task_power)
#            #facts=pyv_vmomihelper.gather_facts(vm)
#
#            #cust=self.customspec
#            #deploy_ovf_PyVmH.customize_vm(vm_obj=vm)
#            #customspec = vim.vm.customization.Specification()
#        else:
#            module.fail_json(msg="VM already exists in the vCenter..! Use networks or customization parameters to customize the existing VM")
#     
#    else:
#        #deploy_ovf = VMwareDeployOvf(module)
#
#        deploy_ovf.upload()
#        deploy_ovf.complete()
#
#        #facts = deploy_ovf.power_on()
#
#        if module.params['networks'] or module.params['customization']:
#            vm_deploy = deploy_ovf.get_vm_obj()
#            deploy_ovf_PyVmH.customize_vm(vm_deploy)
#            myspec=deploy_ovf_PyVmH.customspec
#            task=vm_deploy.CustomizeVM_Task(spec=myspec)
#
##            custom_wait_for_task(task, module)
# 
#            try:
#                wait_for_task(task) 
#            except Exception,e:
#                module.fail_json(msg="Error:%s" % e.message.msg)
#            if task.info.state == 'error':
#                module.fail_json(msg="Error occured: %s" % to_native(task.info.error.msg))
#
#            try:
#               facts = deploy_ovf.vm_power_on(vm_deploy)
#            except Esxeption,e:
#               module.fail_json(msg="Error from vCenter: %s" % e.message.msg)
#
#            #wait_for_task(task)
#            #facts = deploy_ovf.power_on()
#            #module.exit_json(instance=facts)
#        else:
#            try:
#                facts = deploy_ovf.power_on()
#            except Exception,e:
#                module.fail_json(msg="Error: %s" %(e.message.msg))
#            #if task.info.state == 'error':
#            #    module.exit_json(msg="Error occured: %s" % to_native(task.info.error.msg))
#
#    #for item in datacenter.items():
#    #    vobj = item[0]
#
#    #if vm_ovf:
#    #    test1 = pyv_ovf.get_vm()
#    #else:
#    #    module.fail_json(msg="VM doesn't exists invcenter..!")
#
#    #if vm_ovf_helper:
#    #    test2 = pyv_vmomihelper.get_vm()
#    #else:
#    #    module.fail_json(msg="VM doesn't exists invcenter..!")
#
#    #deploy_ovf = VMwareDeployOvf(module)
#    #deploy_ovf.upload()
#    #deploy_ovf.complete()
#    #facts = deploy_ovf.power_on()
#
#    #customize = pyv_vmomihelper.customize_vm(getobj vm instalce object)
#
#    #module.exit_json(instance=pyv_vmomihelper.gather_facts(vm))
#    module.exit_json(instance=facts)
#
#
#if __name__ == '__main__':
#    main()
#
