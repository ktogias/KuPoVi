import React, { useEffect, useRef, useState } from "react";
import * as d3 from "d3";

const KuPoVi = () => {
  const svgRef = useRef();
  const width = 800;
  const height = 600;
  const [data, setData] = useState({ nodes: [], pods: [] });
  const [previousData, setPreviousData] = useState(null);
  const [deploymentColors, setDeploymentColors] = useState({});

  useEffect(() => {
    const fetchData = async () => {
      const backendUrl = window.APP_CONFIG?.BACKEND_URL || "http://localhost:5010";
      try {
        const response = await fetch(`${backendUrl}/api/pods?namespace=default&label=zone&display=label`);
        const newData = await response.json();

        if (JSON.stringify(newData) !== JSON.stringify(previousData)) {
          setData(newData);
          setPreviousData(newData);
        }
      } catch (error) {
        console.error("Error fetching pods:", error);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, [previousData]);

  useEffect(() => {
    if (!data.nodes.length) return;

    const svg = d3.select(svgRef.current).attr("width", width).attr("height", height);

    // Assign colors to deployments
    const updatedColors = { ...deploymentColors };
    const colorScale = d3.scaleOrdinal(d3.schemeCategory10);

    data.pods.forEach((pod) => {
      if (!updatedColors[pod.deployment]) {
        updatedColors[pod.deployment] = colorScale(Object.keys(updatedColors).length);
      }
    });

    setDeploymentColors(updatedColors);

    // Calculate node positions
    const nodeSpacing = width / (data.nodes.length + 1);

    const nodes = [
      ...data.nodes.map((n, i) => ({
        id: n.name,
        type: "node",
        fx: nodeSpacing * (i + 1), // Position nodes evenly horizontally
        fy: height / 2,
      })),
      ...data.pods.map((pod) => ({
        id: pod.name,
        type: "pod",
        parent: pod.node,
        color: updatedColors[pod.deployment],
      })),
    ];

    const links = data.pods
      .filter((pod) => pod.node)
      .map((pod) => ({ source: pod.node, target: pod.name }));

    const simulation = d3.forceSimulation(nodes)
      .force(
        "link",
        d3.forceLink(links)
          .id((d) => d.id)
          .strength(1)
          .distance((d) => (d.target.type === "pod" ? 100 : 200)) // Maintain circular orbit for pods
      )
      .force("charge", d3.forceManyBody().strength(-300))
      .force(
        "radial", // Circular force for pods around nodes
        d3.forceRadial(
          (d) => (d.type === "node" ? 0 : 120), // Radius for pods
          (d) => (d.type === "node" ? d.fx : nodes.find((n) => n.id === d.parent)?.fx || width / 2),
          (d) => (d.type === "node" ? d.fy : nodes.find((n) => n.id === d.parent)?.fy || height / 2)
        )
      )
      .force("collide", d3.forceCollide().radius((d) => (d.type === "node" ? 80 : 40)))
      .on("tick", ticked);

    const link = svg.selectAll(".link")
      .data(links)
      .join("line")
      .attr("class", "link")
      .attr("stroke", "gray");

    const node = svg.selectAll(".node")
      .data(nodes)
      .join("circle")
      .attr("class", "node")
      .attr("r", (d) => (d.type === "node" ? 20 : 10))
      .attr("fill", (d) => d.color || "purple")
      .call(d3.drag().on("start", dragstarted).on("drag", dragged).on("end", dragended));

    const nodeLabels = svg.selectAll(".node-label")
      .data(nodes)
      .join("text")
      .attr("class", "node-label")
      .attr("x", (d) => d.x)
      .attr("y", (d) => d.y - 25)
      .attr("text-anchor", "middle")
      .style("font-size", "12px")
      .style("fill", "black")
      .text((d) => d.id);

    function ticked() {
      link
        .attr("x1", (d) => d.source.x)
        .attr("y1", (d) => d.source.y)
        .attr("x2", (d) => d.target.x)
        .attr("y2", (d) => d.target.y);

      node
        .attr("cx", (d) => d.x)
        .attr("cy", (d) => d.y);

      nodeLabels
        .attr("x", (d) => d.x)
        .attr("y", (d) => d.y - 25);
    }

    function dragstarted(event, d) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      d.fx = d.x;
      d.fy = d.y;
    }

    function dragged(event, d) {
      d.fx = event.x;
      d.fy = event.y;
    }

    function dragended(event, d) {
      if (!event.active) simulation.alphaTarget(0);
      d.fx = null;
      d.fy = null;
    }
  }, [data]);

  return <svg ref={svgRef}></svg>;
};

export default KuPoVi;
