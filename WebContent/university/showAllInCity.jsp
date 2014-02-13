<%@ taglib uri="http://java.sun.com/jsp/jstl/core" prefix="c" %>
<%@ page isELIgnored="false" %>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<c:import url="/meta.html"/>
<title>Lab 8 - Universities</title>
</head>
<body>

<div id="header">
	<c:import url="/header.html"/>
</div><hr>
<h1>All Universities</h1>
<div id="content">
	<div id="paramsCurrent">
		<form class="editCity" action="action?code=modifyCity&id=${parent_id}" method="POST">
			<span class="paramTitle">Name: </span>${parent.name}<br>
			<span class="paramTitle">Population: </span>${parent.population}<br>
			<span class="paramTitle">Square: </span>${parent.square}<br>
			<input type="submit" value="Edit">
		</form>
	</div>
	<div id="toolbar">
		<c:import url="/toolbar.html"/>
	</div>
	<div id="main-info">
		<div id="children-list">
			<table class="normal">
				<tr>
					<th class="thin">v</th><th>Name</th><th>Description</th>
				</tr>
				<c:forEach var="item" items="${data}">
					<c:url var="url" value="action">
						<c:param name="code" value="showOneCountry" />
						<c:param name="parent_id" value="${item.ID}" />
					</c:url>
					<tr>
						<td class="thin"><input type="checkbox"></td>
						<td><a class="generated-data" href="${url}">${item.name}</a></td>
						<td>Departaments count: ${item.departamentsCount}, WWW: ${item.WWW}</td>					
					</tr>
				</c:forEach>
			</table>
		</div>

		<div onclick="close_modal();" id="modal"></div><div id="modal_open"></div>
		<div class="addNew popUpWrapper" id="newItemPopup">
			<div class="popUpContent">
				<form id="newUni" action="action?code=addUniversity&parent_id=${parent.ID}" method="POST">
					<table class="noborder">
						<tr>
							<td>Name:</td>
							<td>
								<input name="name" type="text" />
							</td>
						</tr>
						<tr>
							<td>Amount of Depts:</td>
							<td>
								<input name="departs_count" type="text" />
							</td>
						</tr>
						<tr>
							<td>WWW:</td>
							<td>
								<input name="www" type="text" />
							</td>
						</tr>
						<tr>
							<td>
								<a href="javascript:document.getElementById('newUni').submit()">Add</a>
							</td>
							<td>
								<a href="javascript:close_modal();">Cancel</a>
							</td>
						</tr>
					</table>
				</form>		
			</div>
		</div>
	</div>
</div>

<hr style="clear: both;"><div id="footer">
	<c:import url="/footer.html"/>
</div>

</body>
</html>