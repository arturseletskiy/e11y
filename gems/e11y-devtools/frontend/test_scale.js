import { scaleBand } from "d3-scale";
const scale = scaleBand().domain([0, 1, 2]).range([0, 100]).paddingInner(0.18).paddingOuter(0.06);
console.log(scale(0), scale(1), scale(2), scale.bandwidth());
