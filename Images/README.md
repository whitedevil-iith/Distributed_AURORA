# Images Directory

## Testbed Diagram

The file `Images/Testbed.html` contains an editable SVG-based architecture diagram for the O-RAN testbed.

It documents the key testbed components and network layout used in this project, including:
- MAAS & Ansible controller
- Kubernetes multi-node cluster
- OAI RAN nodes (O-DU, O-CU, O-RU)
- Near-RT RIC and SMO components
- Core network and campus network connectivity
- Managed switch and VLAN topology

## How to use

Open `Images/Testbed.html` in a browser to view the diagram. The file is also editable in vector tools like Inkscape or Illustrator, or in a text editor for manual NIC label updates.

The diagram includes placeholder fields marked with `________` for NIC MAC addresses, IP addresses, and other testbed-specific values. Replace those placeholders with actual values to document your physical or virtual deployment.

## Purpose

This testbed image is intended as a reference architecture for the O-RAN deployment and experiment setup. It helps developers and operators understand the physical and logical network boundaries, server roles, and expected connectivity between components.
