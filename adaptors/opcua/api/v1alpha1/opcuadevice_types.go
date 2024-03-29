package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

const (
	PropertyDataTypeInt64 PropertyDataType = "int64"
	PropertyDataTypeInt32 PropertyDataType = "int32"
	PropertyDataTypeInt16 PropertyDataType = "int16"

	PropertyDataTypeUInt64 PropertyDataType = "uint64"
	PropertyDataTypeUInt32 PropertyDataType = "uint32"
	PropertyDataTypeUInt16 PropertyDataType = "uint16"

	PropertyDataTypeString  PropertyDataType = "string"
	PropertyDataTypeFloat   PropertyDataType = "float"
	PropertyDataTypeDouble  PropertyDataType = "double"
	PropertyDataTypeBoolean PropertyDataType = "boolean"
)

// OPCUADeviceSpec defines the desired state of OPCUADevice
type OPCUADeviceSpec struct {
	ProtocolConfig *OPCUAProtocolConfig `json:"protocol,omitempty"`
	Properties     []DeviceProperty     `json:"properties,omitempty"`
}

type OPCUAProtocolConfig struct {
	// Required: The URL for opc-ua server endpoint.
	URL string `json:"url"`
	// Username for accessing opc-ua server.
	UserName string `json:"userName,omitempty"`
	// Password for accessing opc-ua server.
	Password string `json:"password,omitempty"`
	// Defaults to "None". Valid values are "None", "Basic128Rsa15", "Basic256", "Basic256Sha256", "Aes128Sha256RsaOaep", "Aes256Sha256RsaPss".
	// +kubebuilder:validation:Enum=None;Basic128Rsa15;Basic256;Basic256Sha256;Aes128Sha256RsaOaep;Aes256Sha256RsaPss
	SecurityPolicy string `json:"securityPolicy,omitempty"`
	// Defaults to "None". Valid values are "None", "Sign", and "SignAndEncrypt".
	// +kubebuilder:validation:Enum=None;Sign;SignAndEncrypt
	SecurityMode string `json:"securityMode,omitempty"`
	// Certificate file for accessing opc-ua server.
	CertificateFile string `json:"certificateFile,omitempty"`
	// PrivateKey file for accessing opc-ua server.
	PrivateKeyFile string `json:"privateKeyFile,omitempty"`
}

// DeviceProperty describes an individual device property / attribute like temperature / humidity etc.
type DeviceProperty struct {
	// The device property name.
	Name string `json:"name"`
	// The device property description.
	// +optional
	Description string `json:"description,omitempty"`
	ReadOnly    bool   `json:"readOnly,omitempty"`
	// PropertyDataType represents the type and data validation of the property.
	DataType PropertyDataType `json:"dataType"`
	Visitor  PropertyVisitor  `json:"visitor"`
	Value    string           `json:"value,omitempty"`
}

// The property data type.
// +kubebuilder:validation:Enum=float;double;int64;int32;int16;uint64;uint32;uint16;string;boolean
type PropertyDataType string

type PropertyVisitor struct {
	// Required: The ID of opc-ua node, e.g. "ns=1,i=1005"
	NodeID string `json:"nodeID,omitempty"`
	// The name of opc-ua node
	BrowseName string `json:"browseName,omitempty"`
}

// OPCUADeviceStatus defines the observed state of OPCUADevice
type OPCUADeviceStatus struct {
	Properties []StatusProperties `json:"properties,omitempty"`
}

type StatusProperties struct {
	Name      string           `json:"name,omitempty"`
	Value     string           `json:"value,omitempty"`
	DataType  PropertyDataType `json:"dataType,omitempty"`
	UpdatedAt metav1.Time      `json:"updatedAt,omitempty"`
}

// +kubebuilder:object:root=true
// +k8s:openapi-gen=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="AGE",type="date",JSONPath=".metadata.creationTimestamp"
// +kubebuilder:printcolumn:name="ENDPOINT",type="string",JSONPath=".spec.protocol.url"
// OPCUADevice is the Schema for the OPCUA device API
type OPCUADevice struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   OPCUADeviceSpec   `json:"spec,omitempty"`
	Status OPCUADeviceStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
// OPCUADeviceList contains a list of OPCUA devices
type OPCUADeviceList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []OPCUADevice `json:"items"`
}

func init() {
	SchemeBuilder.Register(&OPCUADevice{}, &OPCUADeviceList{})
}
