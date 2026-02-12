package main

import (
	appsv1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/apps/v1"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	networkingv1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/networking/v1"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi-tls/sdk/v4/go/tls"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		// Generate secure random passwords
		dbPassword, err := random.NewRandomPassword(ctx, "keycloak-db-password", &random.RandomPasswordArgs{
			Length:  pulumi.Int(24),
			Special: pulumi.Bool(true),
		})
		if err != nil {
			return err
		}

		adminPassword, err := random.NewRandomPassword(ctx, "keycloak-admin-password", &random.RandomPasswordArgs{
			Length:  pulumi.Int(16),
			Special: pulumi.Bool(false), // Admin password without special chars for easier login
		})
		if err != nil {
			return err
		}

		// Create namespace for Keycloak
		namespace, err := corev1.NewNamespace(ctx, "keycloak-namespace", &corev1.NamespaceArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name: pulumi.String("keycloak"),
				Labels: pulumi.StringMap{
					"app":     pulumi.String("keycloak"),
					"version": pulumi.String("v1.0.0"),
				},
			},
		})
		if err != nil {
			return err
		}

		// Generate TLS certificate for HTTPS
		privateKey, err := tls.NewPrivateKey(ctx, "keycloak-private-key", &tls.PrivateKeyArgs{
			Algorithm: pulumi.String("RSA"),
			RsaBits:   pulumi.Int(2048),
		})
		if err != nil {
			return err
		}

		cert, err := tls.NewSelfSignedCert(ctx, "keycloak-cert", &tls.SelfSignedCertArgs{
			PrivateKeyPem: privateKey.PrivateKeyPem,
			Subject: &tls.SelfSignedCertSubjectArgs{
				CommonName:   pulumi.String("keycloak.local"),
				Organization: pulumi.String("DevOps Assignment"),
			},
			DnsNames: pulumi.StringArray{
				pulumi.String("keycloak.local"),
				pulumi.String("keycloak"),
				pulumi.String("keycloak.keycloak.svc.cluster.local"),
			},
			ValidityPeriodHours: pulumi.Int(8760), // 1 year
			AllowedUses: pulumi.StringArray{
				pulumi.String("key_encipherment"),
				pulumi.String("digital_signature"),
				pulumi.String("server_auth"),
			},
		})
		if err != nil {
			return err
		}

		// Create TLS secret
		tlsSecret, err := corev1.NewSecret(ctx, "keycloak-tls-secret", &corev1.SecretArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("keycloak-tls"),
				Namespace: namespace.Metadata.Name(),
			},
			Type: pulumi.String("kubernetes.io/tls"),
			StringData: pulumi.StringMap{
				"tls.crt": cert.CertPem,
				"tls.key": privateKey.PrivateKeyPem,
			},
		})
		if err != nil {
			return err
		}

		// Create secrets for database and admin credentials
		dbSecret, err := corev1.NewSecret(ctx, "keycloak-db-secret", &corev1.SecretArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("keycloak-db-credentials"),
				Namespace: namespace.Metadata.Name(),
			},
			StringData: pulumi.StringMap{
				"username": pulumi.String("keycloak"),
				"password": dbPassword.Result,
				"database": pulumi.String("keycloak"),
			},
		})
		if err != nil {
			return err
		}

		adminSecret, err := corev1.NewSecret(ctx, "keycloak-admin-secret", &corev1.SecretArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("keycloak-admin-credentials"),
				Namespace: namespace.Metadata.Name(),
			},
			StringData: pulumi.StringMap{
				"username": pulumi.String("admin"),
				"password": adminPassword.Result,
			},
		})
		if err != nil {
			return err
		}

		// Deploy PostgreSQL database (simplified for compatibility)
		_, err = appsv1.NewDeployment(ctx, "postgres-deployment", &appsv1.DeploymentArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("postgres"),
				Namespace: namespace.Metadata.Name(),
				Labels: pulumi.StringMap{
					"app":       pulumi.String("postgres"),
					"component": pulumi.String("database"),
				},
			},
			Spec: &appsv1.DeploymentSpecArgs{
				Replicas: pulumi.Int(1),
				Selector: &metav1.LabelSelectorArgs{
					MatchLabels: pulumi.StringMap{
						"app": pulumi.String("postgres"),
					},
				},
				Template: &corev1.PodTemplateSpecArgs{
					Metadata: &metav1.ObjectMetaArgs{
						Labels: pulumi.StringMap{
							"app": pulumi.String("postgres"),
						},
					},
					Spec: &corev1.PodSpecArgs{
						Containers: corev1.ContainerArray{
							&corev1.ContainerArgs{
								Name:  pulumi.String("postgres"),
								Image: pulumi.String("postgres:15-alpine"),
								Ports: corev1.ContainerPortArray{
									&corev1.ContainerPortArgs{
										ContainerPort: pulumi.Int(5432),
									},
								},
								Env: corev1.EnvVarArray{
									&corev1.EnvVarArgs{
										Name:  pulumi.String("POSTGRES_DB"),
										Value: pulumi.String("keycloak"),
									},
									&corev1.EnvVarArgs{
										Name: pulumi.String("POSTGRES_USER"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: dbSecret.Metadata.Name(),
												Key:  pulumi.String("username"),
											},
										},
									},
									&corev1.EnvVarArgs{
										Name: pulumi.String("POSTGRES_PASSWORD"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: dbSecret.Metadata.Name(),
												Key:  pulumi.String("password"),
											},
										},
									},
								},
							},
						},
					},
				},
			},
		})
		if err != nil {
			return err
		}

		// Create PostgreSQL service
		_, err = corev1.NewService(ctx, "postgres-service", &corev1.ServiceArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("postgres"),
				Namespace: namespace.Metadata.Name(),
			},
			Spec: &corev1.ServiceSpecArgs{
				Selector: pulumi.StringMap{
					"app": pulumi.String("postgres"),
				},
				Ports: corev1.ServicePortArray{
					&corev1.ServicePortArgs{
						Port:       pulumi.Int(5432),
						TargetPort: pulumi.Int(5432),
					},
				},
			},
		})
		if err != nil {
			return err
		}

		// Deploy Keycloak
		keycloakDeployment, err := appsv1.NewDeployment(ctx, "keycloak-deployment", &appsv1.DeploymentArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("keycloak"),
				Namespace: namespace.Metadata.Name(),
				Labels: pulumi.StringMap{
					"app":       pulumi.String("keycloak"),
					"component": pulumi.String("identity-provider"),
				},
			},
			Spec: &appsv1.DeploymentSpecArgs{
				Replicas: pulumi.Int(1),
				Selector: &metav1.LabelSelectorArgs{
					MatchLabels: pulumi.StringMap{
						"app": pulumi.String("keycloak"),
					},
				},
				Template: &corev1.PodTemplateSpecArgs{
					Metadata: &metav1.ObjectMetaArgs{
						Labels: pulumi.StringMap{
							"app": pulumi.String("keycloak"),
						},
					},
					Spec: &corev1.PodSpecArgs{
						Containers: corev1.ContainerArray{
							&corev1.ContainerArgs{
								Name:  pulumi.String("keycloak"),
								Image: pulumi.String("quay.io/keycloak/keycloak:23.0"),
								Args: pulumi.StringArray{
									pulumi.String("start"),
									pulumi.String("--hostname=keycloak.local"),
									pulumi.String("--https-certificate-file=/opt/keycloak/conf/tls.crt"),
									pulumi.String("--https-certificate-key-file=/opt/keycloak/conf/tls.key"),
									pulumi.String("--https-port=8443"),
									pulumi.String("--http-enabled=false"),
								},
								Ports: corev1.ContainerPortArray{
									&corev1.ContainerPortArgs{
										Name:          pulumi.String("https"),
										ContainerPort: pulumi.Int(8443),
									},
								},
								Env: corev1.EnvVarArray{
									&corev1.EnvVarArgs{
										Name:  pulumi.String("KC_DB"),
										Value: pulumi.String("postgres"),
									},
									&corev1.EnvVarArgs{
										Name:  pulumi.String("KC_DB_URL"),
										Value: pulumi.String("jdbc:postgresql://postgres:5432/keycloak"),
									},
									&corev1.EnvVarArgs{
										Name: pulumi.String("KC_DB_USERNAME"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: dbSecret.Metadata.Name(),
												Key:  pulumi.String("username"),
											},
										},
									},
									&corev1.EnvVarArgs{
										Name: pulumi.String("KC_DB_PASSWORD"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: dbSecret.Metadata.Name(),
												Key:  pulumi.String("password"),
											},
										},
									},
									&corev1.EnvVarArgs{
										Name: pulumi.String("KEYCLOAK_ADMIN"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: adminSecret.Metadata.Name(),
												Key:  pulumi.String("username"),
											},
										},
									},
									&corev1.EnvVarArgs{
										Name: pulumi.String("KEYCLOAK_ADMIN_PASSWORD"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: adminSecret.Metadata.Name(),
												Key:  pulumi.String("password"),
											},
										},
									},
									&corev1.EnvVarArgs{
										Name:  pulumi.String("KC_PROXY"),
										Value: pulumi.String("edge"),
									},
								},
								VolumeMounts: corev1.VolumeMountArray{
									&corev1.VolumeMountArgs{
										Name:      pulumi.String("tls-certs"),
										MountPath: pulumi.String("/opt/keycloak/conf"),
										ReadOnly:  pulumi.Bool(true),
									},
								},
								ReadinessProbe: &corev1.ProbeArgs{
									HttpGet: &corev1.HTTPGetActionArgs{
										Path:   pulumi.String("/realms/master"),
										Port:   pulumi.Int(8443),
										Scheme: pulumi.String("HTTPS"),
									},
									InitialDelaySeconds: pulumi.Int(30),
									PeriodSeconds:       pulumi.Int(10),
								},
								LivenessProbe: &corev1.ProbeArgs{
									HttpGet: &corev1.HTTPGetActionArgs{
										Path:   pulumi.String("/realms/master"),
										Port:   pulumi.Int(8443),
										Scheme: pulumi.String("HTTPS"),
									},
									InitialDelaySeconds: pulumi.Int(60),
									PeriodSeconds:       pulumi.Int(30),
								},
							},
						},
						Volumes: corev1.VolumeArray{
							&corev1.VolumeArgs{
								Name: pulumi.String("tls-certs"),
								Secret: &corev1.SecretVolumeSourceArgs{
									SecretName: tlsSecret.Metadata.Name(),
								},
							},
						},
					},
				},
			},
		})
		if err != nil {
			return err
		}

		// Create Keycloak service
		keycloakService, err := corev1.NewService(ctx, "keycloak-service", &corev1.ServiceArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("keycloak"),
				Namespace: namespace.Metadata.Name(),
			},
			Spec: &corev1.ServiceSpecArgs{
				Selector: pulumi.StringMap{
					"app": pulumi.String("keycloak"),
				},
				Ports: corev1.ServicePortArray{
					&corev1.ServicePortArgs{
						Name:       pulumi.String("https"),
						Port:       pulumi.Int(8443),
						TargetPort: pulumi.Int(8443),
						Protocol:   pulumi.String("TCP"),
					},
				},
				Type: pulumi.String("ClusterIP"),
			},
		})
		if err != nil {
			return err
		}

		// Create Network Policy for security
		_, err = networkingv1.NewNetworkPolicy(ctx, "keycloak-network-policy", &networkingv1.NetworkPolicyArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String("keycloak-network-policy"),
				Namespace: namespace.Metadata.Name(),
			},
			Spec: &networkingv1.NetworkPolicySpecArgs{
				PodSelector: &metav1.LabelSelectorArgs{
					MatchLabels: pulumi.StringMap{
						"app": pulumi.String("keycloak"),
					},
				},
				PolicyTypes: pulumi.StringArray{
					pulumi.String("Ingress"),
					pulumi.String("Egress"),
				},
				Ingress: networkingv1.NetworkPolicyIngressRuleArray{
					&networkingv1.NetworkPolicyIngressRuleArgs{
						Ports: networkingv1.NetworkPolicyPortArray{
							&networkingv1.NetworkPolicyPortArgs{
								Port:     pulumi.Int(8443),
								Protocol: pulumi.String("TCP"),
							},
						},
					},
				},
				Egress: networkingv1.NetworkPolicyEgressRuleArray{
					&networkingv1.NetworkPolicyEgressRuleArgs{
						To: networkingv1.NetworkPolicyPeerArray{
							&networkingv1.NetworkPolicyPeerArgs{
								PodSelector: &metav1.LabelSelectorArgs{
									MatchLabels: pulumi.StringMap{
										"app": pulumi.String("postgres"),
									},
								},
							},
						},
						Ports: networkingv1.NetworkPolicyPortArray{
							&networkingv1.NetworkPolicyPortArgs{
								Port:     pulumi.Int(5432),
								Protocol: pulumi.String("TCP"),
							},
						},
					},
					// Allow DNS
					&networkingv1.NetworkPolicyEgressRuleArgs{
						To: networkingv1.NetworkPolicyPeerArray{
							&networkingv1.NetworkPolicyPeerArgs{
								NamespaceSelector: &metav1.LabelSelectorArgs{
									MatchLabels: pulumi.StringMap{
										"name": pulumi.String("kube-system"),
									},
								},
							},
						},
						Ports: networkingv1.NetworkPolicyPortArray{
							&networkingv1.NetworkPolicyPortArgs{
								Port:     pulumi.Int(53),
								Protocol: pulumi.String("UDP"),
							},
						},
					},
				},
			},
		})
		if err != nil {
			return err
		}

		// Output important information
		ctx.Export("namespace", namespace.Metadata.Name())
		ctx.Export("keycloak-url", pulumi.String("https://keycloak.local:8443"))
		ctx.Export("keycloak-admin-username", adminSecret.StringData.MapIndex(pulumi.String("username")))
		ctx.Export("keycloak-admin-password", adminPassword.Result)
		ctx.Export("keycloak-service", keycloakService.Metadata.Name())
		ctx.Export("deployment-status", keycloakDeployment.Status)

		return nil
	})
}
