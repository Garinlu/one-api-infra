terraform {
    required_providers {
        kind = {
            source  = "tehcyx/kind"
            version = "0.11.0"
        }
        helm = {
            source = "hashicorp/helm"
        }
    }
}

provider "kind" {
}

resource "kind_cluster" "one-api-cluster" {
    name = "one-api-cluster"
    wait_for_ready = true
    kind_config {
        kind = "Cluster"
        api_version = "kind.x-k8s.io/v1alpha4"
        node {
            role = "control-plane"
            kubeadm_config_patches = [
                "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
            ]
            extra_port_mappings {
                container_port = 80
                host_port = 80
                protocol = "TCP"
            }
            extra_port_mappings {
                container_port = 443
                host_port = 443
                protocol = "TCP"
            }
        }
    }
}

provider "helm" {
  kubernetes = {
    host                   = kind_cluster.one-api-cluster.endpoint
    client_certificate     = kind_cluster.one-api-cluster.client_certificate
    client_key             = kind_cluster.one-api-cluster.client_key
    cluster_ca_certificate = kind_cluster.one-api-cluster.cluster_ca_certificate
  }
}

resource "helm_release" "ingress_nginx" {
    name = "one-api-ingress"
    repository = "https://kubernetes.github.io/ingress-nginx"
    version = "4.15.1"
    chart      = "ingress-nginx"
    namespace  = "ingress-nginx"
    create_namespace = true
    timeout = 600

    values = [
        yamlencode({
        controller = {
            hostPort = {
                enabled = true
            }
            service = {
                type = "NodePort"
            }
        }
        })
    ]
}

resource "helm_release" "argocd" {
    name = "argocd"
    repository = "https://argoproj.github.io/argo-helm"
    version = "10.7.2"
    chart      = "argo-cd"
    namespace  = "argocd"
    create_namespace = true
}

provider "aws" {
  region                      = "eu-west-3"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style            = true

  endpoints {
    s3 = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "one-api-frontend"
  acl    = "private"

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  versioning = {
    enabled = true
  }

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  attach_policy = true
  policy        = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${module.s3_bucket.s3_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "bucket_front" {
    bucket = "one-api-frontend"

    index_document {
        suffix = "index.html"
    }

    error_document {
        key = "error.html"
    }
}