export class Page extends React.Component<{ title: string }> {
  @observable open = false;
  render() {
    return <h1>{this.props.title}</h1>;
  }
}
