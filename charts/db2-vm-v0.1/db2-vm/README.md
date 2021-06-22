# DB2 Database on Virtual Machine Helm Chart
A Helm chart for deploying a DB2 Database on OpenShift using a Virtual Machine.

## Prerequisites
Below are prerequisites:
- OpenShift Virtualization installed
- StorageClass created
- A golden VM image already uploaded with DB2 installed

If you want to create a Golden image with a VM template, you could create a template with the YAML shown below, then go to "Virtual Machine Templates" and "Add Source" to import the VM image (ie: using an image hosted in a registry, like this example: quay.io/luisarizmendi/db2).

The template shown below will create the template in the 'openshift' namespace, so all users in the cluster will be able to use it, but you will need access to such namespace (or just remove "namespace: openshift" from the YAML) 

```
kind: Template
apiVersion: template.openshift.io/v1
metadata:
  name: vm-template-db2
  namespace: openshift
  annotations:
    name.os.template.kubevirt.io/db2: DB2 Database
    openshift.io/display-name: DB2 Database
    defaults.template.kubevirt.io/disk: rootdisk
    description: DB2 Database
    defaults.template.kubevirt.io/network: default
    template.kubevirt.io/editable: |
      /objects[0].spec.template.spec.domain.cpu.cores
      /objects[0].spec.template.spec.domain.resources.requests.memory
      /objects[0].spec.template.spec.networks
      /objects[0].spec.template.spec.volumes
      /objects[0].spec.template.spec.domain.devices.disks
    template.openshift.io/bindable: 'false'
    tags: 'hidden,kubevirt,virtualmachine'
    validations: |
      [
        {
          "name": "minimal-required-memory",
          "path": "jsonpath::.spec.domain.resources.requests.memory",
          "rule": "integer",
          "message": "This VM requires at least 2GB of memory.",
          "min": 2147483648
        }
      ]
    iconClass: icon-fedora
    template.kubevirt.io/provider: Luis Arizmendi
    openshift.io/provider-display-name: KubeVirt
  labels:
    os.template.kubevirt.io/fedora32: 'true'
    flavor.template.kubevirt.io/medium: 'true'
    workload.template.kubevirt.io/server: 'true'
    vm.kubevirt.io/template: vm-template-db2
    vm.kubevirt.io/template.namespace: openshift
    template.kubevirt.io/type: base
    workload.template.kubevirt.io/highperformance: 'true'
objects:
  - apiVersion: kubevirt.io/v1alpha3
    kind: VirtualMachine
    metadata:
      labels:
        app: '${NAME}'
        vm.kubevirt.io/template: vm-template-db2
        vm.kubevirt.io/template.revision: '1'
        vm.kubevirt.io/template.version: v0.1
      name: '${NAME}'
    spec:
      dataVolumeTemplates:
        - apiVersion: cdi.kubevirt.io/v1beta1
          kind: DataVolume
          metadata:
            creationTimestamp: null
            name: ${NAME}-datavolume
          spec:
            pvc:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 10Gi
              volumeMode: Filesystem
            source:
              blank: {}
      running: false
      template:
        metadata:
          labels:
            kubevirt.io/domain: '${NAME}'
            kubevirt.io/size: medium
        spec:
          domain:
            cpu:
              cores: 2
              sockets: 1
              threads: 1
            devices:
              disks:
                - name: rootdisk
                  bootOrder: 1
                  disk:
                    bus: virtio
                - name: data
                  disk:
                    bus: virtio
                  serial: DATA
                - disk:
                    bus: virtio
                  name: cloudinitdisk
              interfaces:
                - name: default
                  masquerade: {}
                  model: virtio
              networkInterfaceMultiqueue: true
              rng: {}
            ioThreadsPolicy: shared
            machine:
              type: pc-q35-rhel8.2.0
            resources:
              requests:
                memory: 8Gi
          evictionStrategy: LiveMigrate
          networks:
            - name: default
              pod: {}
          terminationGracePeriodSeconds: 180
          volumes:
            - name: rootdisk
              persistentVolumeClaim:
                claimName: '${PVCNAME}'
            - dataVolume:
                name: ${NAME}-datavolume
              name: 'data'
            - cloudInitNoCloud:
                userData: |-
                  #cloud-config
                  user: db2inst1
                  password: ${CLOUD_USER_PASSWORD}
                  chpasswd: { expire: False }
                  runcmd:
                    -  runuser -l  db2inst1 -c '/db2home/db2inst1/sqllib/adm/db2stop'
                    -  echo "0 $(hostname) 0" > /db2home/db2inst1/sqllib/db2nodes.cfg
                    -  mkdir /data
                    -  mkfs.ext4 /dev/disk/by-id/virtio-DATA
                    -  mount /dev/disk/by-id/virtio-DATA /data
                    -  mv /db2home/* /data
                    -  umount /data
                    -  mount /dev/disk/by-id/virtio-DATA /db2home
                    -  echo '/dev/disk/by-id/virtio-DATA /db2home ext4 defaults   0   1' >> /etc/fstab
                    -  runuser -l  db2inst1 -c '/db2home/db2inst1/sqllib/adm/db2start'
              name: cloudinitdisk
parameters:
  - name: NAME
    description: VM name
    generate: expression
    from: 'db2-[a-z0-9]{16}'
  - name: PVCNAME
    description: Name of the PVC with the disk image
    required: true
  - name: SRC_PVC_NAME
    description: Name of the PVC to clone
    value: db2
  - name: SRC_PVC_NAMESPACE
    description: Namespace of the source PVC
    value: openshift-virtualization-os-images
  - name: CLOUD_USER_PASSWORD
    description: Randomized password for the cloud-init user fedora
    generate: expression
    from: '[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}'
```

## Data injection

Apart from enabling the injetion (see variables below), you will need to create a configmap before launching the helm chart. In that configmap it must be two files: tables.sql and values.sql. 

You can create the config map using the CLI:

```
oc create configmap <configmap name> --from-file=tables.sql --from-file=values.sql
```

The files should look like this:

tables.sql
```
CREATE TABLE publishers(
  publisher_id INT GENERATED BY DEFAULT AS IDENTITY NOT NULL, 
  name         VARCHAR(255) NOT NULL,
  PRIMARY KEY(publisher_id)
);

CREATE TABLE authors( 
  author_id   INT GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  first_name  VARCHAR(100) NOT NULL, 
  middle_name VARCHAR(50) NULL, 
  last_name   VARCHAR(100) NULL,
  PRIMARY KEY(author_id)
);
...
...
...
```

values.sql
```
INSERT INTO genres (genre_id, genre, parent_id) VALUES (69, 'Genres', NULL);
INSERT INTO genres (genre_id, genre, parent_id) VALUES (4, 'Anthropology', 69);
INSERT INTO genres (genre_id, genre, parent_id) VALUES (10, 'Biography', 69);
INSERT INTO genres (genre_id, genre, parent_id) VALUES (17, 'Comics', 69);
...
...
...
```


## Values
Below is a table of each value used to configure this chart.

| Value | Description | Default | Additional Information |
| ----- | ----------- | ------- | ---------------------- |
| `virtualmachine.name` | Name of the Virtual Machine | db2 | - |
| `virtualmachine.userpass` | Password for the db2inst1 user | redhat | - |
| `virtualmachine.resources.cores` | Virtual Machine resources (vCores) | 2 | - |
| `virtualmachine.resources.memory` |Virtual Machine resources (Memory) | 8Gi | - |
| `virtualmachine.storage.storageclass` | StorageClass to be used |  -  | If empty, it will use the dafault StorageClass |
| `virtualmachine.storage.rootdisk.size` | Operating System disk size | 20Gi | - |
| `virtualmachine.storage.rootdisk.access_mode` | Operating System disk access mode| ReadWriteMany| ReadWriteMany must be selected for live migration (StorageClass must support it) |
| `virtualmachine.storage.rootdisk.template_pvc` | PVC name containing the Operating System disk template" | db2 | If using VM template shown above, the default is OK. |
| `virtualmachine.storage.datavol.size` | Data disk size | 5Gi | - |
| `virtualmachine.storage.datavol.access_mode` | Disk access mode | ReadWriteMany | ReadWriteMany must be selected for live migration (StorageClass must support it) |
| `database.data.enabled` | Enable/Disable data injection | false | - |
| `database.data.database_name` | Name for the new Database | newdb | - |
| `database.data.content_configmap` | Configmap name with the values.sql and tables.sql files | - | Be sure that the files in the configmap are named in that way |
| `database.access.console.published` | Database console published with a HTTPS route | true | - |
| `database.access.dataservice.published` | Database  published with a Nodeport | false | - |
| `database.access.dataservice.nodeport` | Nodeport port number to be used to publish the Database | 30500 | Default valid range is 30000-32767 |

