# Analysis APP Helm Chart

## Creating the Helm repo in OpenShift

This Helm chart is part of [my Helm Chart repository](https://github.com/luisarizmendi/helm-chart-repo). If you want to create a repo in OpenShift pointing to these charts, just create this object:

```
apiVersion: helm.openshift.io/v1beta1
kind: HelmChartRepository
metadata:
  name: larizmen-helm-repo
spec:
  name: Luis Arizmendi Helm Charts
  connectionConfig:
    url: https://raw.githubusercontent.com/luisarizmendi/helm-chart-repo/main/packages
```

## Prerequisites
Below are prerequisites:
- PostgreSQL Database
- Kafka Cluster

This Helm chart is able to deploy a postgres database server using the Postgres OpenShift template and the Kafka cluster by using the AMQ Streams Operator (which must be installed previously since it's not instaled by this Chart).

You can also create those backend services by your own:

### PostgreSQL Database

You will need a PostgreSQL Database with the tables needed by the application

First you will need to create the Database. As an example I will show how to create one using the catalog template included in OpenShift, but you can create it in any other way (for example with an Operator)

-1 Create one instance of the "PostgreSQL" template (ie. using the "+Add" in the Developer UI). Use this values:

```
Database Service Name: analysisdb
PostgreSQL Connection Username: analysisadmin
PostgreSQL Connection Password: analysispassword
PostgreSQL Database Name: analysisdb
```

-2 (Optional) Include the "app.openshift.io/runtime=postgresql" and "app.kubernetes.io/part-of=analysis" labels in the Deployment


Once the Database is deployed, you need to create the tables in the Database. You could create a port-forward and create them manually, but you can also use this example where we create a configmap with the pgsql statements and run it with a Job:


-1 Create a configmap with the pgsql commands:

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: pg-script
  namespace: analysis-demo
data:
  pgscript.sh: |-
    #!/bin/bash#
    psql -h analysisdb -p 5432 -U analysisadmin analysisdb  -c "CREATE SCHEMA analysis AUTHORIZATION analysisadmin;"
    psql -h analysisdb -p 5432 -U analysisadmin analysisdb  -c "alter table if exists analysis.LineItems
        drop constraint if exists FK6fhxopytha3nnbpbfmpiv4xgn;"
    psql -h analysisdb -p 5432 -U analysisadmin analysisdb  -c "drop table if exists analysis.LineItems cascade;
    drop table if exists analysis.Orders cascade;
    drop table if exists analysis.OutboxEvent cascade;"
    psql -h analysisdb -p 5432 -U analysisadmin analysisdb  -c "create table analysis.LineItems (
                              itemId varchar(255) not null,
                              item varchar(255),
                              lineItemStatus varchar(255),
                              name varchar(255),
                              order_id varchar(255) not null,
                              primary key (itemId)
    );"

    psql -h analysisdb -p 5432 -U analysisadmin analysisdb  -c "create table analysis.Orders (
                            order_id varchar(255) not null,
                            patientId varchar(255),
                            orderStatus varchar(255),
                            timestamp timestamp,
                            primary key (order_id)
    );"

    psql -h analysisdb -p 5432 -U analysisadmin analysisdb  -c "create table analysis.OutboxEvent (
                                id uuid not null,
                                aggregatetype varchar(255) not null,
                                aggregateid varchar(255) not null,
                                type varchar(255) not null,
                                timestamp timestamp not null,
                                payload varchar(8000),
                                primary key (id)
    );"

    psql -h analysisdb -p 5432 -U analysisadmin analysisdb  -c "alter table if exists analysis.LineItems
        add constraint FK6fhxopytha3nnbpbfmpiv4xgn
            foreign key (order_id)
                references analysis.Orders;"
```

-2 Create a Job using an image with the postgres-client CLI included and make use of the configmap containing the pgsql statements:

```
apiVersion: batch/v1
kind: Job
metadata:
  name: init-db
  namespace: analysis-demo
spec:
  selector: {}
  template:
    metadata:
      name: init-db
    spec:
      containers:
        - name: init-db
          env:      
          - name: PGPASSWORD
            value: analysispassword
          image: quay.io/luisarizmendi/postgres-client
          volumeMounts:
          - name: pgscript
            mountPath: "pgscript"
            readOnly: false
          command: ["/bin/sh","-c"]
          args:
            - cat pgscript/pgscript.sh | /bin/bash
      volumes:
        - name: pgscript
          configMap:
            name: pg-script
      restartPolicy: Never
```

-3 (optional) Remove the Job

For better visualization you can deploy pgweb:

```
kind: Deployment
apiVersion: apps/v1
metadata:
  annotations:
    app.openshift.io/connects-to: >-
      [{"apiVersion":"apps.openshift.io/v1","kind":"DeploymentConfig","name":"analysisdb"}]
  name: pgweb
  namespace: analysis-demo
  labels:
    app: pgweb
    app.kubernetes.io/component: pgweb
    app.kubernetes.io/instance: pgweb
    app.kubernetes.io/part-of: analysis
    app.openshift.io/runtime: postgresql
    app.openshift.io/runtime-namespace: analysis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgweb
  template:
    metadata:
      labels:
        app: pgweb
        deploymentconfig: pgweb
    spec:
      containers:
        - name: pgweb
          image: >-
            sosedoff/pgweb
          ports:
            - containerPort: 8081
              protocol: TCP
---
kind: Service
apiVersion: v1
metadata:
  annotations:
    app.openshift.io/connects-to: >-
      [{"apiVersion":"apps.openshift.io/v1","kind":"DeploymentConfig","name":"analysisdb"}]
  name: pgweb
  namespace: analysis-demo
  labels:
    app: pgweb
    app.kubernetes.io/component: pgweb
    app.kubernetes.io/instance: pgweb
    app.kubernetes.io/part-of: analysis
    app.openshift.io/runtime-version: latest
spec:
  ports:
    - name: 8081-tcp
      protocol: TCP
      port: 8081
      targetPort: 8081
  selector:
    app: pgweb
    deploymentconfig: pgweb
  type: ClusterIP
  sessionAffinity: None
---
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: pgweb
  namespace: analysis-demo
  labels:
    app: pgweb
    app.kubernetes.io/component: pgweb
    app.kubernetes.io/instance: pgweb
    app.kubernetes.io/part-of: analysis
    app.openshift.io/runtime-version: latest
  annotations:
    app.openshift.io/connects-to: >-
      [{"apiVersion":"apps.openshift.io/v1","kind":"DeploymentConfig","name":"analysisdb"}]
spec:
  to:
    kind: Service
    name: pgweb
    weight: 100
  port:
    targetPort: 8081-tcp
  wildcardPolicy: None
```

### Kafka Cluster

This is an example of the steps needed to deploy and configure the Kafka cluster:

-1 Deploy the AMQ Streams Operator (all namespaces)
-2 Create a Kafka instance CRD

```
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: analysis-cluster
  namespace: analysis-demo
spec:
  kafka:
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      log.message.format.version: '2.7'
      inter.broker.protocol.version: '2.7'
    version: 2.7.0
    storage:
      type: ephemeral
    replicas: 3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
  entityOperator:
    topicOperator: {}
    userOperator: {}
  zookeeper:
    storage:
      type: ephemeral
    replicas: 3
```    

-3 Create Kafka topics (check namespace name)

```
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: regularprocess-in
  labels:
    strimzi.io/cluster: analysis-cluster
  namespace:  analysis-demo
spec:
  partitions: 10
  replicas: 3
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: virusprocess-in
  labels:
    strimzi.io/cluster: analysis-cluster
  namespace:  analysis-demo
spec:
  partitions: 10
  replicas: 3
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: orders-in
  labels:
    strimzi.io/cluster: analysis-cluster
  namespace:  analysis-demo
spec:
  partitions: 10
  replicas: 3
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: orders-out
  labels:
    strimzi.io/cluster: analysis-cluster
  namespace:  analysis-demo
spec:
  partitions: 10
  replicas: 3
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: web-updates
  labels:
    strimzi.io/cluster: analysis-cluster
  namespace:  analysis-demo
spec:
  partitions: 10
  replicas: 3
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
```

-4 (optional) Deploy Kafdrop (https://github.com/obsidiandynamics/kafdrop)

```
kind: DeploymentConfig
apiVersion: apps.openshift.io/v1
metadata:
  name: analysis-events-kafdrop
  annotations:
    app.openshift.io/connects-to: >-
      [{"apiVersion":"apps/v1","kind":"StatefulSet","name":"analysis-cluster-kafka"}]
  labels:
    app: kafdrop
    app.kubernetes.io/part-of: analysis
    app.openshift.io/runtime: amq
  annotations:
    app.openshift.io/vcs-uri: 'https://github.com/obsidiandynamics/kafdrop'
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    name: kafdrop
  template:
    metadata:
      name: kafdrop
      labels:
        name: kafdrop
    spec:
      containers:
        - name: kafdrop
          env:
            - name: KAFKA_BROKERCONNECT
              value: "analysis-cluster-kafka-bootstrap:9092"
          imagePullPolicy: IfNotPresent
          image: obsidiandynamics/kafdrop
          ports:
            - containerPort: 9000
              protocol: TCP
          livenessProbe:
            failureThreshold: 3
            initialDelaySeconds: 30
            periodSeconds: 10
            successThreshold: 1
            httpGet:
              path: /actuator/health
              port: 9000
              scheme: HTTP
          readinessProbe:
            failureThreshold: 3
            initialDelaySeconds: 30
            periodSeconds: 10
            successThreshold: 1
            httpGet:
              path: /actuator/health
              port: 9000
              scheme: HTTP
  triggers:
    - type: ConfigChange
---
kind: Service
apiVersion: v1
metadata:
  name: kafdrop
  labels:
    app: kafdrop
spec:
  ports:
    - name: 9000-tcp
      port: 9000
      protocol: TCP
      targetPort: 9000
  selector:
    deploymentconfig: analysis-events-kafdrop
---
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  labels:
    app: kafdrop
  name: kafdrop
spec:
  port:
    targetPort: 9000-tcp
  to:
    kind: Service
    name: kafdrop
    weight: 100
```

## Values
Below is a table of each value used to configure this chart.

| Value | Description | Default | Additional Information |
| ----- | ----------- | ------- | ---------------------- |
| `registry` | Registry where the container images are located | quay.io/analysis | - |
| `kafka.cluster_name` | Name of the Kafka cluster | analysis-cluster | - |
| `kafka.create` | Create kafka resources | true | - |
| `postgres.hostname` | Hostname of the database server | analysisdb | - |
| `postgres.database_name` | Name of the database | analysisdb | - |
| `postgres.schema` | Name of the Schema used | analysis | - |
| `postgres.username` | PostgreSQL username | analysisadmin | - |
| `postgres.password` | PostgreSQL password | analysispassword | - |
| `postgres.create` | Create Postgres database | true | - |


## About the APP

You can check the source code here: https://github.com/luisarizmendi/analysis
