output "nodes" {
  value = {
    (var.region_a) = module.node_a.instance_id
    (var.region_b) = module.node_b.instance_id
  }
}
