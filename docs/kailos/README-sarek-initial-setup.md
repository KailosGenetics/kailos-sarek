#### Local Mac Install

##### On the Mac directly:
```bash
brew install openjdk@17
# For the system Java wrappers to find this JDK, symlink it with
sudo ln -sfn /usr/local/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk

curl -s https://get.nextflow.io | bash
mv nextflow /usr/local/bin/

cd /path/to/kailos-sarek
nextflow run main.nf -profile test,docker --outdir results
```
