#!/bin/bash

cd charts

for i in $(ls)
do 
   cd $i
   for m in $(ls)
   do
       helm package $m
   done
   cd ..
done 


rm -f packages/*


for i in $(ls)
do 
   cd $i
   for m in $(ls *.tgz)
   do
       mv $m ../../packages/
   done
   cd ..
done 

cd ..

helm repo index packages

exit 0